# EORScopeEmployerCosts

Dependency-free Swift package that embeds the EOR Scope dataset of statutory
employer costs, as typed, read-only records.

- 76 countries: employer cost in % and USD per month at an example salary,
  local currency, exchange rate and review date
- 544 employer contribution and statutory extra lines, each with rate, base,
  base factor, floor/ceiling, source URL and date
- 108 declared assumptions (the case each country's total holds for)

Source of the data: the [EOR Scope open dataset](https://eorscope.com/data/)
(CC BY 4.0). The CSV files ship unmodified as SwiftPM resources.

Platforms: macOS 10.15+, iOS 13+, Linux (Swift 5.9+).

## Usage

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/eorscope/eorscope-swift.git", from: "0.1.1"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "EORScopeEmployerCosts", package: "eorscope-swift"),
    ]),
]
```

```swift
import EORScopeEmployerCosts

if let de = EmployerCosts.country("DE") {          // CountrySummary?
    print(de.employerCostPctPrinted)               // percent of gross, as printed on eorscope.com
}
let lines = EmployerCosts.contributions("DE")      // [Contribution]
let europe = EmployerCosts.countries(inRegion: "Europe")
let regions = EmployerCosts.regions()
EmployerCosts.country("FR")?.totalBound(atGrossAnnualLocal: 44755) // .atMost, under 3 x SMIC
```

The package is a lookup library: it returns the figures as exported and
computes nothing. Countries flagged `totalDeclaredFloor` publish an "at least"
figure, not a total: read their `employerCostPct` as "at least". Under
`totalDeclaredCeiling` the modelled contribution base is the highest the law
allows and lines with `inTotal` false come on top. A contribution's `rate`
applies to its `base` times `baseFactor` (1 unless the law builds the base from
more than the salary, as Mexico's integrated base does).

Two countries have a bound that depends on the salary, as eorscope.com prints
it (`totalBoundSalaryRule`, `totalBoundSalaryThresholdLocal`): in Spain the
total is "at least" for a gross annual salary above the maximum contribution
base (the solidarity contribution on pay above it is not modelled), and in
France "at most" below 3 x SMIC (the RGDU relief is not modelled). At the
threshold itself and on the other side, the figure is a total.
`totalBound(atGrossAnnualLocal:)` returns `.atLeast`, `.atMost` or nil, and
`.atLeast` for every declared floor.

For a cost at another salary, use the
[EOR cost calculator](https://eorscope.com/eor-cost-calculator/), which runs
the full computation. How each figure is sourced and checked is set out in the
[methodology](https://eorscope.com/methodology/). Every country has its own
[employer of record page](https://eorscope.com/employer-of-record/) with the
contribution lines and their official sources.

Cost comparison, not legal or tax advice.

## Data in this release

Version 0.1.1 carries the EOR Scope dataset export of 14 November 2026 (commit
`92ef5ea` of [eorscope/employer-costs](https://github.com/eorscope/employer-costs)).
Figures published on eorscope.com after that date are on the site and in later
exports: https://eorscope.com/data/.

## Changes

- 0.1.1: salary-dependent bounds (Spain "at least" above the maximum
  contribution base, France "at most" below 3 x SMIC) read from the dataset's
  new `total_bound_salary_threshold_local` and `total_bound_salary_rule`
  columns, with `totalBound(atGrossAnnualLocal:)`; data from the export of
  14 November 2026.
- 0.1.0: first release, export of 13 October 2026.

## Updating the data

`./sync.sh <dir>` copies the three CSV files and the data licence of a dataset
export (https://eorscope.com/data/) into `Sources/EORScopeEmployerCosts/data/`.
Then run `swift test`.

## Licence

Code: MIT, see LICENSE.

Data (`Sources/EORScopeEmployerCosts/data/`): CC BY 4.0, see
`Sources/EORScopeEmployerCosts/data/LICENSE`. Attribution: EOR Scope,
published by Trésor Kaya EI (Les Créavores), France,
https://eorscope.com/methodology/.
