{-
   Triangles.hs (adapted from triangles.cpp which is (c) The Red Book Authors.)
   Copyright (c) Sven Panne 2013 <svenpanne@gmail.com>
   This file is part of HOpenGL and distributed under a BSD-style license
   See the file libraries/GLUT/LICENSE

   Our first OpenGL program.
-}

import Control.Exception
import Control.Monad
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable
import Graphics.UI.GLUT
import Prelude hiding ( init )
import System.IO

-- TODO: Just for debugging, remove me later.
checkError :: String -> IO ()
checkError functionName = get errors >>= mapM_ reportError
  where reportError e =
          hPutStrLn stderr (showError e ++ " detected in " ++ functionName)
        showError (Error category message) =
          "GL error " ++ show category ++ " (" ++ message ++ ")"

data ShaderSource =
     FileSource FilePath
   | StringSource String

data ShaderInfo = ShaderInfo ShaderType ShaderSource

checked :: (t -> IO ())
        -> (t -> GettableStateVar Bool)
        -> (t -> GettableStateVar String)
        -> String
        -> t
        -> IO ()
checked action getStatus getInfoLog message object = do
   action object
   ok <- get (getStatus object)
   unless ok $ do
      infoLog <- get (getInfoLog object)
      fail (message ++ " log: " ++ infoLog)

compileAndCheck :: Shader -> IO ()
compileAndCheck = checked compileShader compileStatus shaderInfoLog "compile"

getSource :: ShaderSource -> IO String
getSource (FileSource path) = readFile path
getSource (StringSource src) = return src

linkAndCheck :: Program -> IO ()
linkAndCheck = checked linkProgram linkStatus programInfoLog "link"

traceCreation :: Show a => IO a -> IO a
traceCreation create = do
   x <- create
   putStrLn ("Created " ++ show x)
   return x

traceDeletion :: Show a => (a -> IO b) -> a -> IO b
traceDeletion delete x = do
   putStrLn ("Deleting " ++ show x)
   delete x

loadCompileAttach :: Program -> [ShaderInfo] -> IO ()
loadCompileAttach _ [] = return ()
loadCompileAttach program (ShaderInfo shType source : infos) =
   (traceCreation $ createShader shType) `bracketOnError` (traceDeletion deleteObjectName) $ \shader -> do
      src <- getSource source
      shaderSource shader $= [src]
      compileAndCheck shader
      attachShader program shader
      loadCompileAttach program infos

loadShaders :: [ShaderInfo] -> IO Program
loadShaders infos =
   (traceCreation createProgram) `bracketOnError` (traceDeletion deleteObjectName) $ \program -> do
      loadCompileAttach program infos
      linkAndCheck program
      return program

bufferOffset :: Integral a => a -> Ptr b
bufferOffset = plusPtr nullPtr . fromIntegral

vPosition :: AttribLocation
vPosition = AttribLocation 0

data Descriptor = Descriptor VertexArrayObject ArrayIndex NumArrayIndices

init :: IO Descriptor
init = do
  [triangles] <- genObjectNames 1
  bindVertexArrayObject $= Just triangles

  let vertices = [
        Vertex2 (-0.90) (-0.90),  -- Triangle 1
        Vertex2   0.85  (-0.90),
        Vertex2 (-0.90)   0.85 ,
        Vertex2   0.90  (-0.85),  -- Triangle 2
        Vertex2   0.90    0.90 ,
        Vertex2 (-0.85)   0.90 ] :: [Vertex2 GLfloat]
      numVertices = length vertices

  [arrayBuffer] <- genObjectNames 1
  bindBuffer ArrayBuffer $= Just arrayBuffer
  withArray vertices $ \ptr -> do
    let size = fromIntegral (numVertices * sizeOf (head vertices))
    bufferData ArrayBuffer $= (size, ptr, StaticDraw)

  program <- loadShaders [
     ShaderInfo VertexShader (FileSource "triangles.vert"),
     ShaderInfo FragmentShader (FileSource "triangles.frac")]
  currentProgram $= Just program

  let firstIndex = 0
  vertexAttribPointer vPosition $=
    (ToFloat, VertexArrayDescriptor 2 Float 0 (bufferOffset firstIndex))
  vertexAttribArray vPosition $= Enabled

  checkError "init"
  return $ Descriptor triangles firstIndex (fromIntegral numVertices)

display :: Descriptor -> DisplayCallback
display (Descriptor triangles firstIndex numVertices) = do
  clear [ ColorBuffer ]
  bindVertexArrayObject $= Just triangles
  drawArrays Triangles firstIndex numVertices
  flush
  checkError "display"

main :: IO ()
main = do
  (progName, _args) <- getArgsAndInitialize
  initialDisplayMode $= [ RGBAMode ]
  initialWindowSize $= Size 512 512
  initialContextVersion $= (4, 3)

  -- TODO: Just for debugging, remove me later.
  initialContextFlags $= [ DebugContext ]

  initialContextProfile $= [ CoreProfile ]
  _ <- createWindow progName
  descriptor <- init
  displayCallback $= display descriptor
  mainLoop
