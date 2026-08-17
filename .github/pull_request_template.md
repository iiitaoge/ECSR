## State evolution

### X_t

Describe the authoritative state before this change.

### S_i

List the Systems and the Contributions they propose from the read-only snapshot.

### ⊗

Describe composition, order, priority, conflicts, and constraints.

### Φ

Describe the Effects materialized by the single State Update authority.

### X_t+1

Describe the authoritative state after this change.

## Verification

- [ ] `./tests/Conformance.ps1`
- [ ] `./tests/Verify.ps1`
- [ ] No application or platform dependency entered `src`
- [ ] No Matter write escaped `src/Rules/StateUpdateRule.luau`
