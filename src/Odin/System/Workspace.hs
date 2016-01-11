{-# LANGUAGE FlexibleContexts #-}
module Odin.System.Workspace where

import Odin.Data.Common

import Gelatin.GLFW
import Gelatin.Picture

import Data.Renderable
import Data.IORef
import Data.Bits
import Data.Proxy
import Graphics.UI.GLFW
import Graphics.GL.Core33
import Graphics.Text.TrueType
import Control.Varying
import Control.Concurrent
import Control.Monad.Trans.RWS.Strict
import System.Exit
import Linear

runWorkspace :: SplineOf InputEvent (Picture Font ()) () -> IO ()
runWorkspace net = newWorkspace >>= step net
    where step n ws = do
            events <- getWorkspaceInput ws
            let input = foldl addInputEvent (wsRead ws) events
                ws' = ws{ wsRead = input }
                rwst = stepMany events $ runSplineT n
            ((Step (Event ui) _, n'),_,_) <- runRWST rwst input ()

            ws'' <- renderFrame ws' ui
            step (SplineT n') ws''{wsRead = input{_readResources = wsRez ws''}}
          addInputEvent input (CursorMoveEvent x y) =
              let v = realToFrac <$> V2 x y
              in input{ _readCursorPos = v }
          addInputEvent input _ = input

stepMany :: (Monad m, Monoid a) => [a] -> Var m a b -> m (b, Var m a b)
stepMany ([e]) y = runVar y e
stepMany (e:es) y = execVar y e >>= stepMany es
stepMany []     y = runVar y mempty


renderFrame :: Workspace -> Picture Font () -> IO Workspace
renderFrame ws pic = do
    let old = wsCache ws
        rz = wsRez ws

    (fbw,fbh) <- getFramebufferSize $ rezWindow rz
    glViewport 0 0 (fromIntegral fbw) (fromIntegral fbh)
    glClear $ GL_COLOR_BUFFER_BIT .|. GL_DEPTH_BUFFER_BIT

    new <- renderData rz old pic (Proxy :: Proxy [])

    pollEvents
    swapBuffers $ rezWindow rz
    shouldClose <- windowShouldClose $ rezWindow rz
    if shouldClose
    then exitSuccess
    else threadDelay 100
    return $ ws { wsCache = new, wsRez = rz }

getWorkspaceInput :: Workspace -> IO [InputEvent]
getWorkspaceInput ws = do
    -- Read accumulated events this frame
    events <- readIORef (wsRef ws)
    -- Clear input events.
    writeIORef (wsRef ws) []
    return events

newWorkspace :: IO Workspace
newWorkspace = do
    rez <- startupGLFWBackend 800 600 "Odin" Nothing Nothing
    let w = rezWindow rez
    setWindowPos w 400 400

    glEnable GL_BLEND
    glBlendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA

    ref <- newIORef []
    let input i = modifyIORef ref (++ [i])

    setCharCallback w $ Just $ \_ c -> input $
        CharEvent c

    setWindowSizeCallback w $ Just $ \_ w' h' -> input $
        WindowSizeEvent w' h'

    setKeyCallback w $ Just $ \_ k i ks modi -> input $
        KeyEvent k i ks modi

    setMouseButtonCallback w $ Just $ \_ mb mbs modi -> input $
        MouseButtonEvent mb mbs modi

    setCursorPosCallback w $ Just $ \_ x y -> input $
        CursorMoveEvent x y

    setCursorEnterCallback w $ Just $ \_ cs -> input $
        CursorEnterEvent cs

    setScrollCallback w $ Just $ \_ x y -> input $
        ScrollEvent x y

    ---- Not till GLFW-b with 3.1 additions
    --setDropCallback w $ Just $ \_ fs -> do
    --    putStrLn $ "Got files:\n" ++ unlines fs
    --    input $ FileDropEvent fs

    let i = ReadData { _readCursorPos = 0
                     , _readWindowSize = V2 800 600
                     , _readResources = rez
                     , _readDpi = 72
                     }
    return $ Workspace Nothing rez mempty ref i
