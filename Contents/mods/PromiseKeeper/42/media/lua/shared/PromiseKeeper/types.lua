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
---@field chance number|nil Chance threshold [0,1], deterministic per occurranceKey.
---@field cooldownSeconds number|nil Cooldown after successful runs (per promiseId).
---@field retry PKPolicyRetry|nil Retry behavior when the action errors.
---@field expiry PKPolicyExpiry|nil Optional pruning configuration.

---@class PKSituationCandidate
---@field occurranceKey any Stable id for idempotence across reloads.
---@field subject any Non-nil "safe-to-mutate" world object (or payload) handed to the action.
---@field [string] any Additional fields are allowed and passed through via `promiseCtx.situation`.

---@class PKPromiseCtx
---@field promiseId string
---@field occurranceKey any
---@field actionId string
---@field situationKey string
---@field retryCounter number
---@field policy PKPolicy
---@field situation PKSituationCandidate The full candidate (pass-through context).

---@alias PKActionFn fun(subject:any, args:table, promiseCtx:PKPromiseCtx)

---@class PKSubscription
---@field unsubscribe fun()

---@class PKSituationStream
---@field subscribe fun(self:PKSituationStream, onNext:fun(item:any)): PKSubscription

---@alias PKSituationFactoryFn fun(args:table): PKSituationStream

---@class PKPromiseSpec
---@field promiseId string
---@field situationKey string
---@field situationArgs table|nil
---@field actionId string
---@field actionArgs table|nil
---@field policy PKPolicy|nil

---@class PKPromiseHandle
---@field namespace string
---@field promiseId string
---@field started boolean
---@field stop fun() Stop the live subscription (does not delete persisted state).
---@field forget fun() Reset persisted progress for this promise.
---@field status fun(): table|nil Get persisted progress for this promise.
---@field whyNot fun(occurranceKey:any): string|nil Get last whyNot reason for an occurrence.

---@class PKNamespaceHandle
---@field adapters table Convenience reference to PromiseKeeper.adapters
---@field factories table Convenience reference to PromiseKeeper.factories
---@field actions table
---@field situations table
---@field promise fun(self:PKNamespaceHandle, spec:PKPromiseSpec): PKPromiseHandle
---@overload fun(self:PKNamespaceHandle, promiseId:string, situationKey:string, situationArgs:table|nil, actionId:string, actionArgs:table|nil, policy:PKPolicy|nil): PKPromiseHandle
---@field remember fun(self:PKNamespaceHandle)
---@field rememberAll fun(self:PKNamespaceHandle)
---@field forget fun(self:PKNamespaceHandle, promiseId:string)
---@field forgetAll fun(self:PKNamespaceHandle)
---@field listPromises fun(self:PKNamespaceHandle): table
---@field getStatus fun(self:PKNamespaceHandle, promiseId:string): table|nil
---@field whyNot fun(self:PKNamespaceHandle, promiseId:string, occurranceKey:any): string|nil

---@class PKActionRegistry
---@field define fun(actionId:string, actionFn:PKActionFn)
---@field has fun(actionId:string): boolean
---@field list fun(): table

---@class PKSituationRegistry
---@field define fun(situationKey:string, factoryFn:PKSituationFactoryFn)
---@field defineFromPZEvent fun(situationKey:string, eventSource:table, mapEventToCandidate:function)
---@field defineFromLuaEvent fun(situationKey:string, eventSource:table, mapEventToCandidate:function)
-- `mapEventToCandidate(args, ...)` receives `situationArgs` as the first parameter.
---@field searchIn fun(registry:table)
---@field has fun(situationKey:string): boolean
---@field list fun(): table

local Types = {}

-- No runtime helpers are exported from here on purpose.

return Types
