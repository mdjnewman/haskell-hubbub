module Main where

import Network.Hubbub
  ( Callback(Callback)
  , From(From)
  , HttpResource(HttpResource)
  , HubbubConfig(HubbubConfig)
  , HubbubSqLiteConfig(HubbubSqLiteConfig)
  , HubbubEnv
  , LeaseSeconds(LeaseSeconds)
  , Secret(Secret)
  , ServerUrl(ServerUrl)
  , Topic(Topic)
  , initializeHubbubSqLite
  , httpResourceFromText
  , shutdownHubbub
  , subscribe
  , unsubscribe
  , publish )

import Prelude (Int)
import Control.Applicative ((<$>),(<*>))
import Control.Monad (return,(=<<))
import Control.Monad.IO.Class (liftIO)
import Data.Bool (Bool(False))
import Data.Functor (fmap)
import Data.Function (($),(.),const)
import Data.Maybe (Maybe(Nothing,Just),maybe,fromMaybe)
import Data.String (String)
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types.Status (status400,status202)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO)

import Web.Scotty
  ( ActionM
  , Parsable
  , get
  , middleware
  , param
  , post
  , rescue
  , reqHeader
  , scotty
  , status
  , text )

port :: Int
port = 5000

main :: IO ()
main = do
  hubbub <- initializeHubbubSqLite hubbubConf hubbubSqLiteConfig
  scotty port (scottyM hubbub)
  shutdownHubbub hubbub

  where 
    scottyM hubbub = do
      middleware logStdoutDev
      get "/subscriptions"  $ listSubscriptionHandler hubbub
      post "/subscriptions" $ doSubscriptionHandler hubbub
      post "/publish"       $ publishHandler hubbub

    hubbubConf         = HubbubConfig 1 1 1 serverUrl defaultLeaseTmOut
    hubbubSqLiteConfig = HubbubSqLiteConfig . Just $ "/tmp/hubbub.db"
    defaultLeaseTmOut  = LeaseSeconds 1800
    serverUrl          = ServerUrl (HttpResource False "localhost" port "" [])


listSubscriptionHandler :: HubbubEnv -> ActionM ()
listSubscriptionHandler _ = text "haha not implemented"

data Mode = Subscribe | Unsubscribe 

doSubscriptionHandler :: HubbubEnv -> ActionM ()
doSubscriptionHandler env = do
  mode <- (parseMode =<<) <$> optionalParam "hub.mode" 
  top  <- topicParam
  cb   <- callbackParam
  
  fromMaybe (badRequest "") $ doSubscription <$> mode <*> top <*> cb

  where
    parseMode :: String -> Maybe Mode
    parseMode "subscribe"   = Just Subscribe
    parseMode "unsubscribe" = Just Unsubscribe
    parseMode _             = Nothing

    doSubscription Subscribe   = doSubscribe
    doSubscription Unsubscribe = doUnsubscribe    
    
    doSubscribe top cb = do
      ls   <- fmap LeaseSeconds <$> optionalParam "hub.lease_seconds"
      sec  <- fmap Secret  <$> optionalParam "hub.secret"
      from <- fmap (From . TL.toStrict) <$> reqHeader "From"            
      liftIO $ subscribe env top cb ls sec from
      status status202
      
    doUnsubscribe top cb = do
      liftIO $ unsubscribe env top cb
      status status202

publishHandler :: HubbubEnv -> ActionM ()
publishHandler hubbub = do
  topic <- topicParam
  maybe (badRequest "Invalid topic") (liftIO . publish hubbub) topic

topicParam :: ActionM (Maybe Topic)
topicParam = fmap Topic <$> httpResourceParam "hub.topic"

callbackParam :: ActionM (Maybe Callback)
callbackParam = fmap Callback <$> httpResourceParam "hub.callback"

httpResourceParam :: TL.Text -> ActionM (Maybe HttpResource)
httpResourceParam = fmap (httpResourceFromText . TL.toStrict =<<) . optionalParam 

optionalParam :: Parsable a => TL.Text -> ActionM (Maybe a)
optionalParam n = fmap Just (param n) `rescue` const (return Nothing)

require :: TL.Text -> Maybe a -> ActionM ()
require msg = maybe (badRequest msg) (const $ return ())

badRequest :: TL.Text -> ActionM ()
badRequest msg = do
  status status400
  text msg
