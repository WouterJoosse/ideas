{-# LANGUAGE RankNTypes #-}
-----------------------------------------------------------------------------
-- Copyright 2011, Open Universiteit Nederland. This file is distributed
-- under the terms of the GNU General Public License. For more information,
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-----------------------------------------------------------------------------
module Ideas.Service.ServiceList (serviceList, exerciselistS) where

import Ideas.Common.Library hiding (apply, applicable, derivation, ready)
import Ideas.Common.Utils (Some(..))
import Data.List (sortBy)
import Data.Ord
import Ideas.Service.BasicServices
import Ideas.Service.FeedbackScript.Syntax
import Ideas.Service.FeedbackText
import Ideas.Service.ProblemDecomposition (problemDecomposition, replyType)
import Ideas.Service.RulesInfo
import Ideas.Service.State
import Ideas.Service.Types
import qualified Ideas.Service.Diagnose as Diagnose
import qualified Ideas.Service.Submit as Submit

------------------------------------------------------
-- Querying a service

serviceList :: [Service]
serviceList =
   [ derivationS, allfirstsS, onefirstS, readyS
   , stepsremainingS, applicableS, allapplicationsS
   , applyS, generateS
   , examplesS, submitS, diagnoseS
   , onefirsttextS, findbuggyrulesS
   , submittextS, derivationtextS
   , feedbacktextS
   , problemdecompositionS
   , rulelistS, rulesinfoS, strategyinfoS
   ]

------------------------------------------------------
-- Basic services

derivationS :: Service
derivationS = makeService "derivation"
   "Returns one possible derivation (or: worked-out example) starting with the \
   \current expression. The first optional argument lets you configure the \
   \strategy, i.e., make some minor modifications to it. Rules used and \
   \intermediate expressions are returned in a list." $
   derivation ::: typed -- maybeType strategyCfgType :-> stateType :-> errorType (derivationType (tuple2 ruleType envType) contextType)

allfirstsS :: Service
allfirstsS = makeService "allfirsts"
   "Returns all next steps that are suggested by the strategy. See the \
   \onefirst service to get only one suggestion. For each suggestion, a new \
   \state, the rule used, and the location where the rule was applied are \
   \returned." $
   allfirsts ::: typed -- stateType :-> errorType (listType (tuple2 stepInfoType stateType))

onefirstS :: Service
onefirstS = makeService "onefirst"
   "Returns a possible next step according to the strategy. Use the allfirsts \
   \service to get all possible steps that are allowed by the strategy. In \
   \addition to a new state, the rule used and the location where to apply \
   \this rule are returned." $
   onefirst ::: stateType :-> errorType (elemType (tuple2 stepInfoType stateType))

readyS :: Service
readyS = makeService "ready"
   "Test if the current expression is in a form accepted as a final answer. \
   \For this, the strategy is not used." $
   ready ::: typed -- stateType :-> boolType

stepsremainingS :: Service
stepsremainingS = makeService "stepsremaining"
   "Computes how many steps are remaining to be done, according to the \
   \strategy. For this, only the first derivation is considered, which \
   \corresponds to the one returned by the derivation Ideas.Service." $
   stepsremaining ::: typed -- stateType :-> errorType intType

applicableS :: Service
applicableS = makeService "applicable"
   "Given a current expression and a location in this expression, this service \
   \yields all rules that can be applied at this location, regardless of the \
   \strategy." $
   applicable ::: typed -- locationType :-> stateType :-> listType ruleType

allapplicationsS :: Service
allapplicationsS = makeService "allapplications"
   "Given a current expression, this service yields all rules that can be \
   \applied at a certain location, regardless wether the rule used is buggy \
   \or not. Some results are within the strategy, others are not." $
   allapplications ::: typed -- stateType :-> listType (tuple3 ruleType locationType stateType)

applyS :: Service
applyS = makeService "apply"
   "Apply a rule at a certain location to the current expression. If this rule \
   \was not expected by the strategy, we deviate from it. If the rule cannot \
   \be applied, this service call results in an error." $
   apply ::: ruleType :-> locationType :-> Tag "args" envType :-> stateType :-> errorType stateType

generateS :: Service
generateS = makeService "generate"
   "Given an exercise code and a difficulty level (optional), this service \
   \returns an initial state with a freshly generated expression." $
   generateWith ::: typed -- stdGenType :-> exerciseType :-> maybeType difficultyType :-> errorType stateType

examplesS :: Service
examplesS = makeService "examples"
   "This services returns a list of example expresssions that can be solved \
   \with an exercise. These are the examples that appear at the page generated \
   \for each exercise. Also see the generate service, which returns a random \
   \start term." $
   (map snd . examples) ::: exerciseType :-> listType termType

findbuggyrulesS :: Service
findbuggyrulesS = makeService "findbuggyrules"
   "Search for common misconceptions (buggy rules) in an expression (compared \
   \to the current state). It is assumed that the expression is indeed not \
   \correct. This service has been superseded by the diagnose Ideas.Service." $
   findbuggyrules ::: stateType :-> termType :-> listType (tuple3 ruleType locationType envType)

submitS :: Service
submitS = deprecate $ makeService "submit"
   "Analyze an expression submitted by a student. Possible answers are Buggy, \
   \NotEquivalent, Ok, Detour, and Unknown. This service has been superseded \
   \by the diagnose Ideas.Service." $
   Submit.submit ::: stateType :-> termType :-> Submit.submitType

diagnoseS :: Service
diagnoseS = makeService "diagnose"
   "Diagnose an expression submitted by a student. Possible diagnosis are \
   \Buggy (a common misconception was detected), NotEquivalent (something is \
   \wrong, but we don't know what), Similar (the expression is pretty similar \
   \to the last expression in the derivation), Expected (the submitted \
   \expression was anticipated by the strategy), Detour (the submitted \
   \expression was not expected by the strategy, but the applied rule was \
   \detected), and Correct (it is correct, but we don't know which rule was \
   \applied)." $
   Diagnose.diagnose ::: stateType :-> termType :-> Diagnose.diagnosisType

------------------------------------------------------
-- Services with a feedback component

onefirsttextS :: Service
onefirsttextS = makeService "onefirsttext"
   "Similar to the onefirst service, except that the result is now returned as \
   \a formatted text message. The optional string is for announcing the event \
   \leading to this service call (which can influence the returned result)." $
   onefirsttext ::: scriptType :-> stateType :-> maybeType stringType
                :-> tuple2 (messageType textType) (maybeType stateType)

derivationtextS :: Service
derivationtextS = makeService "derivationtext"
   "Similar to the derivation service, but the rules appearing in the derivation \
   \have been replaced by a short description of the rule." $
   derivationtext ::: scriptType :-> stateType :-> errorType (derivationType (Tag "ruletext" stringType) contextType)

submittextS :: Service
submittextS = deprecate $ makeService "submittext"
   "Similar to the submit service, except that the result is now returned as \
   \a formatted text message. The expression 'submitted' by the student is sent \
   \in plain text (and parsed by the exercise's parser). \
   \The boolean in the \
   \result specifies whether the submitted term is accepted and incorporated \
   \in the new state." $
   submittext ::: scriptType :-> stateType :-> stringType :-> messageAndState

feedbacktextS :: Service
feedbacktextS = makeService "feedbacktext"
   "Textual feedback for diagnose Ideas.Service. Experimental." $
   feedbacktext ::: scriptType :-> stateType :-> termType :-> messageAndState

-- Helper type for submittext and feedbacktext: reorders elements, and inserts
-- some extra tags
messageAndState :: Type a (Bool, Text, State a)
messageAndState = Iso (f <-> g) tp
 where
   f ((a, b), c) = (a, b, c)
   g (a, b, c)   = ((a, b), c)
   tp  = tuple2 (messageType (tuple2 (Tag "accept" boolType) textType)) stateType

------------------------------------------------------
-- Problem decomposition service

problemdecompositionS :: Service
problemdecompositionS = makeService "problemdecomposition"
   "Strategy service developed for the SURF project Intelligent Feedback for a \
   \binding with the MathDox system on linear algebra exercises. This is a \
   \composite service, and available for backwards compatibility." $
   problemDecomposition ::: maybeType idType  :-> stateType :-> maybeType (Tag "answer" termType) :-> errorType replyType

------------------------------------------------------
-- Reflective services

exerciselistS :: [Some Exercise] -> Service
exerciselistS list = makeService "exerciselist"
   "Returns all exercises known to the system. For each exercise, its domain, \
   \identifier, a short description, and its current status are returned." $
   allExercises list ::: listType (tuple3 (Tag "exerciseid" stringType) (Tag "description" stringType) (Tag "status" stringType))

rulelistS :: Service
rulelistS = makeService "rulelist"
   "Returns all rules of a particular exercise. For each rule, we return its \
   \name (or identifier), whether the rule is buggy, and whether the rule was \
   \expressed as an observable rewrite rule. See rulesinfo for more details \
   \about the rules." $
   allRules ::: exerciseType :-> listType (tuple4 (Tag "name" stringType) (Tag "buggy" boolType) (Tag "arguments" intType) (Tag "rewriterule" boolType))

rulesinfoS :: Service
rulesinfoS = makeService "rulesinfo"
   "Returns a list of all rules of a particular exercise, with many details \
   \including Formal Mathematical Properties (FMPs) and example applications." $
   () ::: rulesInfoType

strategyinfoS :: Service
strategyinfoS = makeService "strategyinfo"
   "Returns the representation of the strategy of a particular exercise." $
   (toStrategy . strategy) ::: exerciseType :-> strategyType

allExercises :: [Some Exercise] -> [(String, String, String)]
allExercises = map make . sortBy (comparing f)
 where
   f :: Some Exercise -> String
   f (Some ex) = showId ex
   make (Some ex) =
      (showId ex, description ex, show (status ex))

allRules :: Exercise a -> [(String, Bool, Int, Bool)]
allRules = map make . ruleset
 where
   make r  = (showId r, isBuggy r, length $ getRefs r, isRewriteRule r)