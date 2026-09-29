# hs.caffeinate.currentAssertions crashes on a successful null IOKit result

Prepared for review; no upstream issue or pull request has been submitted.

## Observed problem

Six independent Hammerspoon 1.1.1 (6936), native ARM64 crash reports on macOS
26.6.2 (25G83) recorded the same failure between September 26 and 29, 2026:

```
EXC_BREAKPOINT / SIGTRAP
*** CFRelease() called with NULL ***
CFRelease.cold.2
CFRelease
caffeinate_currentAssertions
precallC
```

A personal idle-monitor script periodically called `hs.caffeinate.currentAssertions()`
from a timer to detect applications preventing display sleep. The call was wrapped
in Lua `pcall`, which cannot recover from this native trap. The latest recorded
crash entered through `HSTimer callback:`. Raw crash reports and the personal
configuration are deliberately excluded; the above is the relevant sanitized evidence.

Expected: return a table, including an empty table when there are no assertions.
Actual: the whole app terminates when IOKit returns success without a dictionary.

## Root cause and evidence

Upstream baseline: `23e387e2805a9890066366e0ac96c71b27f0cfd5`.
`extensions/caffeinate/libcaffeinate.m` checks only the IOReturn status, converts
`assertions`, then unconditionally calls `CFRelease(assertions)`.

The installed SDK header describes a dictionary on success. However, Apple's
[published implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMAssertions.c)
contains a concrete success-without-output path in `_copyAssertionsByProcess`:
after a successful `_copyPMServerObject`, a zero-length flattened array causes
`goto exit` before assigning `*AssertionsByPid`. The successful return code is
preserved. Hammerspoon initializes the output to NULL, so this path leaves it NULL.
Allocation-failure paths can also leave the output unset.

This source explains how the condition can occur; it does not prove that an empty
list was the trigger in each recorded crash, or that the published source exactly
matches the installed macOS binary. The native stack and controlled regression
establish the unsafe Hammerspoon behavior independently.

## Reproduction

### Natural, intermittent reproduction

In a disposable Hammerspoon test configuration:

```lua
assertionProbe = hs.timer.doEvery(1, function()
    local ok, result = pcall(hs.caffeinate.currentAssertions)
    print(ok, type(result))
end)
-- Stop the probe with: assertionProbe:stop()
```

This exercises the same operation as the observed timer. It does not guarantee a
crash: the system must produce the null-output condition. Do not disable system
services or other applications' power assertions to force it. This configuration
was not installed or run against the user's normal Hammerspoon session.

### Deterministic native regression

The adjacent standalone harness includes the actual `libcaffeinate.m`, registers
its Lua API, and executes `currentAssertions()` through real Lua/LuaSkin. Only the
IOKit query is substituted, to supply four controlled outcomes. It does not copy
the production algorithm and requires no production test hooks or Xcode project
changes. The CLI child process isolates the intentional baseline crash.

Requirements: macOS, Command Line Tools, Python 3, and a built Hammerspoon app
containing LuaSkin.framework. By default it uses `/Applications/Hammerspoon.app`;
`--frameworks /path/to/Hammerspoon.app/Contents/Frameworks` overrides that location.

From the repository root, test the fix:

```sh
python3 scripts/caffeinate-regression/run.py
```

For a deterministic before/after comparison:

```sh
baseline_dir=$(mktemp -d)
git show 23e387e2805a9890066366e0ac96c71b27f0cfd5:extensions/caffeinate/libcaffeinate.m > "$baseline_dir/libcaffeinate.m"
python3 scripts/caffeinate-regression/run.py --source "$baseline_dir/libcaffeinate.m" --expect-null-crash
python3 scripts/caffeinate-regression/run.py
```

The baseline command intentionally crashes a separate test process once and may
produce a macOS diagnostic report. It does not quit the installed application.

| IOKit outcome | Baseline | Patched |
| --- | --- | --- |
| Success, NULL output | SIGTRAP | Empty Lua table |
| Error, NULL output | Empty Lua table | Empty Lua table |
| Success, empty dictionary | Empty Lua table | Empty Lua table |
| Success, populated dictionary | PID and assertion fields preserved | Same |

Each non-crashing scenario is exercised 100 times. Checks concern observable Lua
results and process survival, not formatting or the particular form of the guard.

## Solution evaluation

1. **Handle NULL alongside the existing error case (chosen).** Two changed lines
   plus a comment; preserves the documented table return type and existing error
   behavior. Skips both object conversion and CFRelease for a missing dictionary.
2. **Guard only CFRelease.** Prevents this trap, but converting a null object can
   return nil rather than the documented table. Less suitable for callers.
3. **Return nil or raise a Lua error.** Makes failure explicit but changes the API
   contract and conflates a legitimate empty result with failure. Not needed here.
4. **Use pmset from Lua.** A possible local workaround, but adds process management,
   text parsing, and timing concerns without fixing the public API.
5. **Restart the app automatically or poll less often.** Does not correct the defect.

No public signature changes. Existing error handling still returns an empty table;
this fix does not claim to distinguish all query failures from zero assertions.
No unrelated caffeinate functions or personal scripts are changed.

## Validation and remaining limits

- Compiled actual upstream and patched native module with Apple's clang, linking
  real macOS frameworks and the installed Hammerspoon 1.1.1 LuaSkin framework.
- Baseline NULL scenario reproduced SIGTRAP (Python subprocess return code -5).
- Patched NULL, error, empty, and populated scenarios each passed 100 calls.
- Baseline error, empty, and populated scenarios each passed 100 calls.
- Full application/XCTest build not performed: full Xcode is not installed.
- No patched app installation, signing validation, sleep/wake soak test, or claim
  that the intermittent system condition has been reproduced naturally.

Before an upstream submission, run the normal project build/tests with full Xcode
and optionally use a separate patched app for a real-world soak test. The native
regression can also link against that build's LuaSkin framework.
