-- PromiseKeeper/types.lua — shared EmmyLua surface for IDEs.

-- This file is intentionally "types only". It exists to make the v2 API easier to use
-- in Lua tooling (EmmyLua annotations) without impacting runtime behavior.

---@class PKPolicyRetry
---@field maxRetries number|nil How many retries after failures (0 disables retries).
---@field delaySeconds number|nil Minimum delay between retries.

---@class PKPolicyExpiry
---@field enabled boolean|nil Enable/disable pruning (safety valve).
---@field ttlSeconds number|nil How long unfulfilled occurrences may live before pruning.

---@class PKPolicy
---@field maxRuns number|nil Total number of successful runs allowed for a promiseId.
---@field chance number|nil Chance threshold [0,1], deterministic per occurrenceId.
---@field cooldownSeconds number|nil Cooldown after successful runs (per promiseId).
---@field retry PKPolicyRetry|nil Retry behavior when the action errors.
---@field expiry PKPolicyExpiry|nil Optional pruning configuration.

---@class PKSituationCandidate
---@field occurrenceId any Stable id for idempotence across reloads.
---@field subject any Non-nil "safe-to-mutate" world object (or payload) handed to the action.
---@field [string] any Additional fields are allowed and passed through via `promiseCtx.situation`.

---@class PKPromiseCtx
---@field promiseId string
---@field occurrenceId any
---@field actionId string
---@field situationFactoryId string
---@field retryCounter number
---@field policy PKPolicy
---@field situation PKSituationCandidate The full candidate (pass-through context).

---@alias PKActionFn fun(subject:any, args:table, promiseCtx:PKPromiseCtx)

---@class PKSubscription
---@field unsubscribe fun()

---@class PKSituationStream
---@field subscribe fun(self:PKSituationStream, onNext:fun(item:any)): PKSubscription

---@alias PKSituationFactoryFn fun(args:table): PKSituationStream

---@class PKNamespaceHandle
---@field defineAction fun(self:PKNamespaceHandle, actionId:string, actionFn:PKActionFn)
---@field defineSituationFactory fun(self:PKNamespaceHandle, situationFactoryId:string, factoryFn:PKSituationFactoryFn)
---@field promise fun(self:PKNamespaceHandle, promiseId:string, situationFactoryId:string, situationArgs:table|nil, actionId:string, actionArgs:table|nil, policy:PKPolicy|nil)
---@field remember fun(self:PKNamespaceHandle)
---@field rememberAll fun(self:PKNamespaceHandle)
---@field forget fun(self:PKNamespaceHandle, promiseId:string)
---@field forgetAll fun(self:PKNamespaceHandle)
---@field listPromises fun(self:PKNamespaceHandle): table
---@field getStatus fun(self:PKNamespaceHandle, promiseId:string): table|nil
---@field whyNot fun(self:PKNamespaceHandle, promiseId:string, occurrenceId:any): string|nil

local Types = {}

-- No runtime helpers are exported from here on purpose.

return Types
