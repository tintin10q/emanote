{-# LANGUAGE DeriveAnyClass #-}

module Emanote.View.Export (renderGraphExport) where

import Data.Aeson (ToJSON)
import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Emanote.Model (Model)
import Emanote.Model qualified as M
import Emanote.Model.Graph qualified as G
import Emanote.Model.Link.Rel qualified as Rel
import Emanote.Model.Link.Resolve qualified as Resolve
import Emanote.Model.Title qualified as Tit
import Emanote.Route (LMLRoute, lmlRouteCase)
import Emanote.Route qualified as R
import Emanote.Route.SiteRoute qualified as SR
import Emanote.Route.SiteRoute.Class (lmlSiteRoute)
import Optics.Operators ((^.))
import Relude

data Export = Export
  { version :: Word,
    files :: Map Text SourceFile
  }
  deriving stock (Generic)
  deriving anyclass (ToJSON)

currentVersion :: Word
currentVersion = 1

-- | A source file in `Model`
data SourceFile = SourceFile
  { title :: Text,
    filePath :: Text,
    parentNote :: Maybe Text,
    url :: Text,
    meta :: Aeson.Value,
    links :: [Link]
  }
  deriving stock (Generic)
  deriving anyclass (ToJSON)

data Link = Link
  { unresolvedRelTarget :: Rel.UnresolvedRelTarget,
    resolvedRelTarget :: Rel.ResolvedRelTarget Text
  }
  deriving stock (Generic)
  deriving anyclass (ToJSON)

renderGraphExport :: Model -> LByteString
renderGraphExport model =
  let notes_ =
        M.modelNoteMetas model & Map.mapKeys lmlRouteKey
          & Map.map
            ( \(tit, r, meta_) ->
                let k = lmlRouteKey r
                 in SourceFile
                      (Tit.toPlain tit)
                      k
                      (toText . lmlSourcePath <$> G.parentLmlRoute r)
                      (SR.siteRouteUrl model $ lmlSiteRoute r)
                      meta_
                      (fromMaybe [] $ Map.lookup k rels)
            )
      rels =
        Map.fromListWith (<>) $
          M.modelNoteRels model <&> \rel ->
            let from_ = lmlRouteKey $ rel ^. Rel.relFrom
                to_ = rel ^. Rel.relTo
                toTarget =
                  Resolve.resolveUnresolvedRelTarget model to_
                    <&> SR.siteRouteUrlStatic model
             in (from_, one $ Link to_ toTarget)
      export = Export currentVersion notes_
   in Aeson.encode export

-- An unique key to represent this LMLRoute in the exported JSON
--
-- We use the source path consistently.
lmlRouteKey :: LMLRoute -> Text
lmlRouteKey =
  toText . R.encodeRoute . R.lmlRouteCase

-- Path of the LML note
lmlSourcePath :: LMLRoute -> FilePath
lmlSourcePath =
  R.encodeRoute . lmlRouteCase
