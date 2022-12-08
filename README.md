# Reward Vault: Type Safe Checkpointing POC

This Repo contains a proof of concept for a pattern that leverages Solidity's
type system to enforce checkpointing before calling mutating functions. This is
accomplished by creating "stale" types that wrap the state of the app that
expose a `getUpdated` function. The "stale" versions of the state does not
expose any mutating functions. In order for a programmer to mutate the state of
the app they _must_ call `getUpdated` before hand.