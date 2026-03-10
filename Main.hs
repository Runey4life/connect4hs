{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (MVar, newMVar, modifyMVar_, readMVar)
import Control.Exception (finally)
import Control.Monad (forM_, forever)
import Data.Aeson (ToJSON (..), object, (.=), encode, decode)
import Data.Aeson.Types (Value (..))
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Network.WebSockets as WS
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.Wai.Application.Static as Static
import WaiAppStatic.Types (defaultWebAppSettings)
import Web.Scotty (scottyApp, get, file, middleware)
import Data.IORef

-- ─── Game Types ──────────────────────────────────────────────────────────────

data Player = Red | Yellow deriving (Eq, Show)

type Cell  = Maybe Player
type Board = [[Cell]]   -- columns, bottom→top

rows, cols :: Int
rows = 6
cols = 7

data GameState = GameState
  { gsBoard   :: Board
  , gsCurrent :: Player
  , gsWinner  :: Maybe Player
  , gsDraw    :: Bool
  } deriving (Show)

-- ─── JSON serialisation ──────────────────────────────────────────────────────

cellToText :: Cell -> Text
cellToText Nothing       = "empty"
cellToText (Just Red)    = "red"
cellToText (Just Yellow) = "yellow"

playerToText :: Player -> Text
playerToText Red    = "red"
playerToText Yellow = "yellow"

stateToJSON :: GameState -> Value
stateToJSON gs = object
  [ "board"   .= [ [ cellToText (getCell (gsBoard gs) c r)
                    | c <- [0..cols-1] ]
                  | r <- [0..rows-1] ]
  , "current" .= playerToText (gsCurrent gs)
  , "winner"  .= fmap playerToText (gsWinner gs)
  , "draw"    .= gsDraw gs
  ]

-- ─── Game Logic ──────────────────────────────────────────────────────────────

emptyBoard :: Board
emptyBoard = replicate cols []

getCell :: Board -> Int -> Int -> Cell
getCell board c r
  | c < 0 || c >= cols = Nothing
  | r < 0 || r >= rows = Nothing
  | otherwise = let col = board !! c
                in if r < length col then col !! r else Nothing

dropPiece :: Board -> Int -> Player -> Maybe Board
dropPiece board c player
  | c < 0 || c >= cols          = Nothing
  | length (board !! c) >= rows  = Nothing
  | otherwise =
      let (before, col:after) = splitAt c board
      in Just (before ++ [col ++ [Just player]] ++ after)

checkWin :: Board -> Player -> Bool
checkWin board player = any checkLine allLines
  where
    target = Just player
    allCells = [(c,r) | c <- [0..cols-1], r <- [0..rows-1]]
    dirs = [(1,0),(0,1),(1,1),(1,-1)]
    allLines = [ [(c+i*dc, r+i*dr) | i <- [0..3]]
               | (c,r) <- allCells, (dc,dr) <- dirs ]
    checkLine line = all (\(c,r) -> getCell board c r == target) line

isFull :: Board -> Bool
isFull = all (\col -> length col >= rows)

nextPlayer :: Player -> Player
nextPlayer Red    = Yellow
nextPlayer Yellow = Red

initialState :: GameState
initialState = GameState emptyBoard Red Nothing False

applyMove :: GameState -> Int -> GameState
applyMove gs col
  | isJust (gsWinner gs) || gsDraw gs = gs   -- game over
  | otherwise =
      case dropPiece (gsBoard gs) col (gsCurrent gs) of
        Nothing       -> gs  -- invalid move
        Just newBoard ->
          let player = gsCurrent gs
              won    = checkWin newBoard player
              draw   = not won && isFull newBoard
          in GameState
               { gsBoard   = newBoard
               , gsCurrent = if won || draw then player else nextPlayer player
               , gsWinner  = if won then Just player else Nothing
               , gsDraw    = draw
               }

-- ─── WebSocket Server ────────────────────────────────────────────────────────

type GameRef = IORef GameState

wsApp :: GameRef -> WS.ServerApp
wsApp ref pending = do
  conn <- WS.acceptRequest pending
  WS.withPingThread conn 30 (return ()) $ do
    -- Send initial state
    gs <- readIORef ref
    WS.sendTextData conn (encode (stateToJSON gs))
    -- Listen for moves
    forever $ do
      msg <- WS.receiveData conn :: IO BL.ByteString
      case decode msg :: Maybe Value of
        Just (Object o) -> do
          case lookup "col" (o) of
            _ -> return ()
        _ -> return ()
      -- Parse column from raw text
      let txt = TL.toStrict (TL.decodeUtf8 msg)
      case T.stripPrefix "{\"col\":" txt >>= T.stripSuffix "}" of
        Just n -> case reads (T.unpack n) :: [(Int,String)] of
          [(col,"")] -> do
            modifyIORef ref (\s -> applyMove s col)
            newGs <- readIORef ref
            WS.sendTextData conn (encode (stateToJSON newGs))
          _ -> return ()
        Nothing -> return ()

-- ─── HTTP + WS combined app ──────────────────────────────────────────────────

main :: IO ()
main = do
  ref <- newIORef initialState
  let port = 8080
  putStrLn $ "Connect 4 running on http://0.0.0.0:" ++ show port
  staticApp <- scottyApp $ do
    get "/" $ file "static/index.html"
    get "/index.html" $ file "static/index.html"
  let app = WaiWS.websocketsOr
              WS.defaultConnectionOptions
              (wsApp ref)
              staticApp
  Warp.run port app
