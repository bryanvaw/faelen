# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users
One person (the owner) using Faelen on their own Android phone, quickly, in daily life: logging a purchase right after paying, checking what is left on a card or in a monthly category before spending. Philippines-based (PHP).

## Product Purpose
Faelen is a local-first personal app with several modules (Media, Vault; Planner and Budget planned). Budget tracks money on-device: cards/accounts with balances, income and expense transactions, monthly budgets per category, and a monthly summary. Success: logging a transaction takes seconds and "how much is left" is answered at a glance.

## Positioning
No account, no server, no bank link: everything stays on the phone, in the same app as the user's other personal data, with the Faelen cat-and-outline identity instead of a generic finance look.

## Capabilities and Constraints
- Single currency: Philippine peso (PHP). Amounts are stored as integer centavos, never doubles.
- First version: cards/accounts with balances, transactions (income/expense, category, date, note), monthly budgets by category with progress, monthly summary (in / out / left, spending by category).
- Later (not v1): recurring bills, savings goals, CSV export, encrypted backup.
- Storage: SQLite via the existing `EntryDatabase` pattern (its own tables), not the Media JSON blob. Backup should later join the existing export.
- Cards are generic bank-style cards (user picks a color and network per card); they are not tied to the user's real bank cards, and no real card numbers are stored.

## Brand Commitments
Existing Faelen design language applies: flat outlined style (bold black outlines, hard offset shadows, bright status colors, coral accent, no gradients), Outfit headings and DM Sans body, light and dark palettes, a distinct cat mark per module (Budget: black-and-white tuxedo cat with a coin). User wants the Budget screen to look and work like today's banking apps, with a card-style UI.

## Evidence on Hand
No real transactions or card data exist yet; any sample data must be synthetic and labelled.

## Product Principles
- On-device and private; never imply a bank connection.
- Money correctness first: integer centavos, clear income vs expense, no silent rounding.
- Fast entry beats completeness: the common case (an expense on the main card) is a few taps.
- One consistent Faelen identity across modules.
