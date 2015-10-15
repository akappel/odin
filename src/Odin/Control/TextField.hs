{-# LANGUAGE TupleSections #-}
module Odin.Control.TextField (
    defaultTextField,
    textField,
) where

import Odin.Data.Common
import Odin.Control.Common
import Odin.Control.TextInput
import Odin.GUI
import Control.Monad.Trans.RWS.Strict
import Control.Monad.Trans.Class
import Control.Lens hiding ((<~))
import Linear
import Gelatin.Core.Rendering
import Data.Monoid

defaultTextField :: TextField
defaultTextField = mutate emptyTextField $ do
    textFieldLabel .= (mempty, PlainText "empty label" $ V4 0.5 0.5 0.5 1)
    textFieldInput .= defaultTextInput
    textFieldError .= (mempty, PlainText "no errors" $ V4 1 0 0 1)

textField :: Varying Transform -> Maybe TextField -> Odin TextField
textField vt Nothing = textField vt $ Just defaultTextField
textField vt (Just t) = do
    offset <- lift $ textFieldLabelSize t
    let inputTfrm = (Transform (offset * V2 1 0) 1 0 <>) <$> vt
        errorTfrm = (Transform (offset * V2 0 1) 0.8 0 <>) <$> vt
        label = (,snd $ _textFieldLabel t) <$> vt
        inactiveInput = inactiveTextInput inputTfrm $ _textFieldInput t
        err = (,snd $ _textFieldError t) <$> errorTfrm
        inactive = TextField <$> label
                             <*> inactiveInput
                             <*> err
    fromInactive <- fst <$> gui inactive
                                (clickInTextInput $ _textFieldInput <$> inactive)

    let activeInput = activeTextInput inputTfrm $ _textFieldInput fromInactive
        active = TextField <$> label
                           <*> activeInput
                           <*> err
    fst <$> gui active
                (clickOutTextInput $ _textFieldInput <$> active)

textFieldLabelSize :: (Monad m, Monoid w)
                   => TextField -> (RWST ReadData w s m) (V2 Float)
textFieldLabelSize t = do
    offset <- textSize $ t^.textFieldLabel._2.plainTextString
    let V2 w h = offset + V2 2 0
    return $ V2 w (if h < 16 then 16 else h)
