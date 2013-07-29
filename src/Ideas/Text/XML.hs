-----------------------------------------------------------------------------
-- Copyright 2013, Open Universiteit Nederland. This file is distributed
-- under the terms of the GNU General Public License. For more information,
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-- A datatype, parser, and pretty printer for XML documents. Re-exports
-- functions defined elsewhere.
--
-----------------------------------------------------------------------------
module Ideas.Text.XML
   ( XML, Attr, AttrList, Element(..), InXML(..)
   , XMLBuilder, makeXML
   , parseXML, showXML, compactXML, findAttribute
   , children, Attribute(..), fromBuilder, findChild, getData
   , BuildXML(..)
   , module Data.Monoid, munless, mwhen
   ) where

import Data.Char
import Data.Foldable (toList)
import Data.Monoid
import Ideas.Text.XML.Interface hiding (parseXML)
import qualified Data.Sequence as Seq
import qualified Ideas.Text.XML.Interface as I

----------------------------------------------------------------
-- Datatype definitions

-- two helper types for attributes
type XML      = Element
type Attr     = Attribute  -- (String, String)
type AttrList = Attributes -- [Attr]

class InXML a where
   toXML       :: a -> XML
   listToXML   :: [a] -> XML
   fromXML     :: Monad m => XML -> m a
   listFromXML :: Monad m => XML -> m [a]
   -- default definitions
   listToXML = Element "list" [] . map (Right . toXML)
   listFromXML xml
      | name xml == "list" && null (attributes xml) =
           mapM fromXML (children xml)
      | otherwise = fail "expecting a list tag"

----------------------------------------------------------------
-- XML parser (a scanner and a XML tree constructor)

parseXML :: String -> Either String XML
parseXML input = do
   xml <- I.parseXML input
   return (ignoreLayout xml)

ignoreLayout :: XML -> XML
ignoreLayout (Element n as xs) =
   let f = either (Left . trim) (Right . ignoreLayout)
   in Element n as (map f xs)

indentXML :: XML -> XML
indentXML = rec 0
 where
   rec i (Element n as xs) =
      let ipl  = i+2
          cd j = Left ('\n' : replicate j ' ')
          f    = either (\x -> [cd ipl, Left x]) (\x -> [cd ipl, Right (rec ipl x)])
          body | null xs   = xs
               | otherwise = concatMap f xs ++ [cd i]
      in Element n as body

showXML :: XML -> String
showXML = (++"\n") . show . indentXML . ignoreLayout

compactXML :: XML -> String
compactXML = show . ignoreLayout

----------------------------------------------------------------
-- XML builders

infix 3 .=.

class Monoid a => BuildXML a where
   (.=.)     :: String -> String -> a   -- attribute
   unescaped :: String -> a             -- parsed character data (unescaped!)
   builder   :: Element -> a            -- (named) xml element
   tag       :: String -> a -> a        -- tag (with content)
   -- functions with a default
   string   :: String -> a -- escaped text
   text     :: Show s => s -> a -- escaped text with Show class
   element  :: String -> [a] -> a
   emptyTag :: String -> a
   -- implementations
   string     = unescaped . escape
   text       = string . show
   element s  = tag s . mconcat
   emptyTag s = tag s mempty

data XMLBuilder = BS (Seq.Seq Attr) (Seq.Seq (Either String Element))

-- local helper
fromBS :: XMLBuilder -> (AttrList, Content)
fromBS (BS as elts) = (toList as, toList elts)

instance Monoid XMLBuilder where
   mempty = BS mempty mempty
   mappend (BS as1 elts1) (BS as2 elts2) =
      BS (as1 <> as2) (elts1 <> elts2)

instance BuildXML XMLBuilder where
   n .=. s   = BS (Seq.singleton (n := escapeAttr s)) mempty
   unescaped = BS mempty . Seq.singleton . Left
   builder   = BS mempty . Seq.singleton . Right
   tag s     = builder . uncurry (Element s) . fromBS

makeXML :: String -> XMLBuilder -> XML
makeXML s = uncurry (Element s) . fromBS

mwhen :: Monoid a => Bool -> a -> a
mwhen True  a = a
mwhen False _ = mempty

munless :: Monoid a => Bool -> a -> a
munless = mwhen . not

escapeAttr :: String -> String
escapeAttr = concatMap f
 where
   f '<' = "&lt;"
   f '&' = "&amp;"
   f '"' = "&quot;"
   f c   = [c]

fromBuilder :: XMLBuilder -> Maybe Element
fromBuilder m =
   case fromBS m of
      ([], [Right a]) -> Just a
      _               -> Nothing

escape :: String -> String
escape = concatMap f
 where
   f '<' = "&lt;"
   f '>' = "&gt;"
   f '&' = "&amp;"
   f c   = [c]

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse