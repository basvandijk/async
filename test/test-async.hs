{-# LANGUAGE ScopedTypeVariables,DeriveDataTypeable #-}
module Main where

import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.HUnit

import Test.HUnit

import Control.Concurrent.Async
import Control.Exception
import Data.Typeable
import Data.IORef
import Control.Concurrent
import Control.Monad
import Data.Maybe
import System.Timeout

import Prelude hiding (catch)

main = defaultMain tests

tests = [
    testCase "async_wait"        async_wait
  , testCase "async_waitCatch"   async_waitCatch
  , testCase "async_exwait"      async_exwait
  , testCase "async_exwaitCatch" async_exwaitCatch
  , testCase "withasync_waitCatch" withasync_waitCatch
  , testCase "withasync_functionReturned_threadKilled"
              withasync_functionReturned_threadKilled
  , testCase "withasync_synchronousException_threadKilled"
              withasync_synchronousException_threadKilled
  , testCase "withasync_timeoutException_rethrown"
              withasync_timeoutException_rethrown
  , testGroup "async_cancel_rep" $
      replicate 1000 $
         testCase "async_cancel"       async_cancel
  , testCase "async_poll"        async_poll
  , testCase "async_poll2"       async_poll2
  , testCase "withasync_waitCatch_blocked" withasync_waitCatch_blocked
  , testGroup "race" $
    [ testCase "right_terminate_normally"
           race_right_terminate_normally
    , testCase "left_terminate_normally"
           race_left_terminate_normally
    , testCase "right_terminate_by_synchronous_exception"
           race_right_terminate_by_synchronous_exception
    , testCase "left_terminate_by_synchronous_exception"
           race_left_terminate_by_synchronous_exception
    , testCase "right_terminates_normally_kills_left"
           race_right_terminates_normally_kills_left
    , testCase "left_terminates_normally_kills_right"
           race_left_terminates_normally_kills_right
    , testCase "right_terminates_by_asynchronous_exception_kills_both"
           race_right_terminates_by_asynchronous_exception_kills_both
    , testCase "left_terminates_by_asynchronous_exception_kills_right"
           race_left_terminates_by_asynchronous_exception_kills_right
    , testCase "foo" foo
    ]
 ]

value = 42 :: Int

data TestException = TestException deriving (Eq,Show,Typeable)
instance Exception TestException

async_waitCatch :: Assertion
async_waitCatch = do
  a <- async (return value)
  r <- waitCatch a
  case r of
    Left _  -> assertFailure ""
    Right e -> e @?= value

async_wait :: Assertion
async_wait = do
  a <- async (return value)
  r <- wait a
  assertEqual "async_wait" r value

async_exwaitCatch :: Assertion
async_exwaitCatch = do
  a <- async (throwIO TestException)
  r <- waitCatch a
  case r of
    Left e  -> fromException e @?= Just TestException
    Right _ -> assertFailure ""

async_exwait :: Assertion
async_exwait = do
  a <- async (throwIO TestException)
  (wait a >> assertFailure "") `catch` \e -> e @?= TestException

withasync_waitCatch :: Assertion
withasync_waitCatch = do
  withAsync (return value) $ \a -> do
    r <- waitCatch a
    case r of
      Left _  -> assertFailure ""
      Right e -> e @?= value

withasync_functionReturned_threadKilled :: Assertion
withasync_functionReturned_threadKilled = do
  a <- withAsync (threadDelay 1000000) $ return
  r <- waitCatch a
  case r of
    Left e  -> fromException e @?= Just ThreadKilled
    Right _ -> assertFailure ""

withasync_synchronousException_threadKilled :: Assertion
withasync_synchronousException_threadKilled = do
  mv <- newEmptyMVar
  catchIgnore $ withAsync (threadDelay 1000000) $ \a -> do
    putMVar mv a
    throwIO DivideByZero
  a <- takeMVar mv
  r <- waitCatch a
  case r of
    Left e  -> fromException e @?= Just ThreadKilled
    Right _ -> assertFailure ""

catchIgnore :: IO a -> IO ()
catchIgnore m = void m `catch` \(e :: SomeException) -> return ()

-- This test requires the SomeAsyncException type
-- which is only available in base >= 4.7
withasync_timeoutException_rethrown :: Assertion
withasync_timeoutException_rethrown = do
  mv <- newEmptyMVar
  timeout 100000 $ withAsync (threadDelay 1000000) $ \a -> do
    putMVar mv a
    threadDelay 1000000
  a <- takeMVar mv
  r <- waitCatch a
  case r of
    Left e  -> fromException e @?= Just ThreadKilled
    Right _ -> assertFailure ""

async_cancel :: Assertion
async_cancel = do
  a <- async (return value)
  cancelWith a TestException
  r <- waitCatch a
  case r of
    Left e -> fromException e @?= Just TestException
    Right r -> r @?= value

async_poll :: Assertion
async_poll = do
  a <- async (threadDelay 1000000)
  r <- poll a
  when (isJust r) $ assertFailure ""
  r <- poll a   -- poll twice, just to check we don't deadlock
  when (isJust r) $ assertFailure ""

async_poll2 :: Assertion
async_poll2 = do
  a <- async (return value)
  wait a
  r <- poll a
  when (isNothing r) $ assertFailure ""
  r <- poll a   -- poll twice, just to check we don't deadlock
  when (isNothing r) $ assertFailure ""

withasync_waitCatch_blocked :: Assertion
withasync_waitCatch_blocked = do
  r <- withAsync (newEmptyMVar >>= takeMVar) waitCatch
  case r of
    Left e ->
        case fromException e of
            Just BlockedIndefinitelyOnMVar -> return ()
            Nothing -> assertFailure $ show e
    Right () -> assertFailure ""

race_right_terminate_normally :: Assertion
race_right_terminate_normally = do
  r <- race (threadDelay 100000 >> return 1)
            (threadDelay 10000  >> return 'x')
  r @?= (Right 'x')

race_left_terminate_normally :: Assertion
race_left_terminate_normally = do
  r <- race (threadDelay 10000  >> return 1)
            (threadDelay 100000 >> return 'x')
  r @?= (Left 1)

race_right_terminate_by_synchronous_exception :: Assertion
race_right_terminate_by_synchronous_exception = do
  r <- try (race (threadDelay 100000 >> return 1)
                 (threadDelay 10000  >> throwIO DivideByZero))
  case r of
    Left e -> e @?= DivideByZero
    _ -> assertFailure ""

race_left_terminate_by_synchronous_exception :: Assertion
race_left_terminate_by_synchronous_exception = do
  r <- try (race (threadDelay 10000  >> throwIO DivideByZero)
                 (threadDelay 100000 >> return 'x'))
  case r of
    Left e -> e @?= DivideByZero
    _ -> assertFailure ""

foo :: Assertion
foo = do
  r <- try $ withAsync (threadDelay 10000  >> throwIO DivideByZero) $ \aLeft ->
             withAsync (threadDelay 100000 >> return 'x') $ \aRight ->
               waitEither aLeft aRight
  case r of
    Left e -> e @?= DivideByZero
    _ -> assertFailure ""

race_right_terminates_normally_kills_left :: Assertion
race_right_terminates_normally_kills_left = do
  ref <- newIORef False
  r <- race (threadDelay 100000 >> writeIORef ref True)
            (threadDelay 10000  >> return 'x')
  leftCompleted <- readIORef ref
  assertBool "" $ not leftCompleted && r == Right 'x'

race_left_terminates_normally_kills_right :: Assertion
race_left_terminates_normally_kills_right = do
  ref <- newIORef False
  r <- race (threadDelay 10000  >> return 1)
            (threadDelay 100000 >> writeIORef ref True)
  rightCompleted <- readIORef ref
  assertBool "" $ not rightCompleted && r == Left 1

race_right_terminates_by_asynchronous_exception_kills_both :: Assertion
race_right_terminates_by_asynchronous_exception_kills_both = do
  leftRef  <- newIORef False
  rightRef <- newIORef False

  timeout 1000 $
    race (threadDelay 10000 >> writeIORef leftRef  True)
         (threadDelay 10000 >> writeIORef rightRef True)

  leftCompleted  <- readIORef leftRef
  rightCompleted <- readIORef rightRef

  assertBool "" $ not leftCompleted && not rightCompleted

race_left_terminates_by_asynchronous_exception_kills_right :: Assertion
race_left_terminates_by_asynchronous_exception_kills_right = do
  mv <- newEmptyMVar

  forkIO $ do
    threadDelay 100000
    leftTid <- takeMVar mv
    throwTo leftTid ThreadKilled

  r <- try $ race (do leftTid <- myThreadId
                      putMVar mv leftTid
                      threadDelay 1000000
                      return 1)
                  (do threadDelay 1000000
                      return 'x')

  r @?= Left ThreadKilled
