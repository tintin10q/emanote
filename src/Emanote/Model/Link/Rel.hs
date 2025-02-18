{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TemplateHaskell #-}

module Emanote.Model.Link.Rel where

import Data.Aeson (ToJSON)
import Data.IxSet.Typed (Indexable (..), IxSet, ixFun, ixList)
import Data.IxSet.Typed qualified as Ix
import Data.Map.Strict qualified as Map
import Emanote.Model.Note (Note, noteDoc, noteRoute)
import Emanote.Pandoc.Markdown.Syntax.WikiLink qualified as WL
import Emanote.Route (LMLRoute, ModelRoute)
import Emanote.Route qualified as R
import Emanote.Route.SiteRoute.Type qualified as SR
import Optics.Operators as Lens ((^.))
import Optics.TH (makeLenses)
import Relude
import Text.Pandoc.Definition qualified as B
import Text.Pandoc.LinkContext qualified as LC

-- | A relation from one note to anywhere in the model.
--
-- Target will remain unresolved in the `Rel`, and can be resolved at a latter
-- time (eg: during rendering).
data Rel = Rel
  { -- The note containing this relation
    _relFrom :: LMLRoute,
    -- The target of the relation (can be a note or anything)
    _relTo :: UnresolvedRelTarget,
    -- | The relation context in LML
    _relCtx :: [B.Block]
  }
  deriving stock (Eq, Ord, Show)

-- | A link target that has not been resolved (using model) yet.
--
-- Resolving this may or may not result in a resource in the model. The ADT
-- constructors capture the different possible types of links the user is
-- allowed to link to.
data UnresolvedRelTarget
  = URTWikiLink (WL.WikiLinkType, WL.WikiLink)
  | URTResource ModelRoute
  | URTVirtual SR.VirtualRoute
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (ToJSON)

type RelIxs = '[LMLRoute, UnresolvedRelTarget]

type IxRel = IxSet RelIxs Rel

instance Indexable RelIxs Rel where
  indices =
    ixList
      (ixFun $ one . _relFrom)
      (ixFun $ one . _relTo)

makeLenses ''Rel

noteRels :: Note -> IxRel
noteRels note =
  extractLinks . LC.queryLinksWithContext $ note ^. noteDoc
  where
    extractLinks :: Map Text (NonEmpty ([(Text, Text)], [B.Block])) -> IxRel
    extractLinks m =
      Ix.fromList $
        flip concatMap (Map.toList m) $ \(url, instances) -> do
          flip mapMaybe (toList instances) $ \(attrs, ctx) -> do
            target <- parseUnresolvedRelTarget attrs url
            pure $ Rel (note ^. noteRoute) target ctx

unresolvedRelsTo :: ModelRoute -> [UnresolvedRelTarget]
unresolvedRelsTo r =
  let wls = either (WL.allowedWikiLinks . R.lmlRouteCase) WL.allowedWikiLinks $ R.modelRouteCase r
   in (URTWikiLink <$> toList wls)
        <> [URTResource r]

-- | Parse a relative URL string for later resolution.
parseUnresolvedRelTarget :: [(Text, Text)] -> Text -> Maybe UnresolvedRelTarget
parseUnresolvedRelTarget attrs url = do
  WL.delineateLink attrs url >>= \case
    Left wl ->
      pure $ URTWikiLink wl
    Right fp ->
      fmap URTVirtual (SR.decodeVirtualRoute fp)
        <|> fmap URTResource (R.mkModelRouteFromFilePath fp)

-- | An `UnresolvedRelTarget` that has been resolved.
--
-- See @Model.Link.Resolve@ for actual resolution logic.
data ResolvedRelTarget a
  = RRTMissing
  | RRTAmbiguous (NonEmpty a)
  | RRTFound a
  deriving stock (Eq, Show, Ord, Functor, Generic)
  deriving anyclass (ToJSON)

resolvedRelTargetFromCandidates :: [a] -> ResolvedRelTarget a
resolvedRelTargetFromCandidates xs =
  case nonEmpty xs of
    Nothing ->
      RRTMissing
    Just (x :| []) ->
      RRTFound x
    Just xs' ->
      RRTAmbiguous xs'
