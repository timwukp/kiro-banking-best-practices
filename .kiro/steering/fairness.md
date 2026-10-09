---
inclusion: fileMatch
fileMatchPattern: ["**/*model*.*", "**/*scor*.*", "**/*decision*.*", "**/*pricing*.*", "**/*credit*.*", "**/*underwrit*.*"]
---
# Fairness & Bias Guidelines (MAS FEAT Principles)

Included when you work on files whose names suggest models, scoring, decisioning, pricing, credit or underwriting logic. Maintainers: adjust `fileMatchPattern` to where decision logic lives in your repository.

## When Generating Financial Logic

- Flag any code that makes decisions based on protected characteristics (race, gender, age, religion, nationality)
- Ensure fee calculations are applied consistently across customer segments
- Make credit scoring logic explainable and auditable: return or log the reason codes or main factors behind each decision
- Warn the user if ML model inputs include demographic proxies (postal code as proxy for ethnicity, etc.)

## When Reviewing Code

- Check that approval/rejection logic does not discriminate
- Verify interest rates and fees are calculated uniformly
- Ensure risk assessments use only legitimate financial factors
- Confirm that error handling treats all customer segments equally

## Accountability

- A human developer is always accountable for code quality, regardless of AI assistance. Present your changes as proposals for review, not as approved logic.
- When you generate or change financial decision logic, state this in your summary and recommend review by a domain expert (for example credit risk or model risk) before merge.
- Automated decisions need an explanation path for customers: make sure each decision records the inputs and reasons needed to explain it.
- Prompt logging for the audit trail of AI-assisted development is a Kiro administrator console setting. You cannot see or change it; if the user asks about it, refer them to their Kiro administrator.
