{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TemplateHaskell #-}

module Emanote.Model.SData where

import Data.Aeson qualified as Aeson
import Data.Aeson.Extra.Merge qualified as AesonMerge
import Data.Data (Data)
import Data.IxSet.Typed (Indexable (..), IxSet, ixGen, ixList)
import Data.List.NonEmpty qualified as NE
import Data.Yaml qualified as Yaml
import Emanote.Route qualified as R
import Optics.TH (makeLenses)
import Relude

-- | `S` for "structured". Refers to a per-route data file represented by Aeson
-- value.  Example: /foo/bar.yaml file
data SData = SData
  { _sdataValue :: Aeson.Value,
    -- | Location of this data file
    _sdataRoute :: R.R 'R.Yaml
  }
  deriving stock (Eq, Ord, Data, Show, Generic)
  deriving anyclass (Aeson.ToJSON)

type SDataIxs = '[R.R 'R.Yaml]

type IxSData = IxSet SDataIxs SData

instance Indexable SDataIxs SData where
  indices =
    ixList
      (ixGen $ Proxy @(R.R 'R.Yaml))

makeLenses ''SData

parseSDataCascading :: R.R 'R.Yaml -> NonEmpty ByteString -> Either Text SData
parseSDataCascading r bs = do
  vals <- traverse (first (show @Text) . Yaml.decodeEither') bs
  let val = mergeAesons vals
  pure $ SData val r

-- | Later values override former.
mergeAesons :: NonEmpty Aeson.Value -> Aeson.Value
mergeAesons =
  NE.last . NE.scanl1 mergeAeson

mergeAeson :: Aeson.Value -> Aeson.Value -> Aeson.Value
mergeAeson = AesonMerge.lodashMerge
