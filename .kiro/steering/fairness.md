# Fairness & Bias Guidelines (MAS FEAT Principles)

## When Generating Financial Logic

- Flag any code that makes decisions based on protected characteristics (race, gender, age, religion, nationality)
- Ensure fee calculations are applied consistently across customer segments
- Credit scoring logic must be explainable and auditable
- Alert if ML model inputs include demographic proxies (postal code as proxy for ethnicity, etc.)

## When Reviewing Code

- Check that approval/rejection logic does not discriminate
- Verify interest rates and fees are calculated uniformly
- Ensure risk assessments use only legitimate financial factors
- Confirm that error handling treats all customer segments equally

## Accountability

- A human developer is always accountable for code quality, regardless of AI assistance
- AI-generated financial decision logic requires domain expert review
- All automated decisions must have an explanation path for customers
- Prompt logging must be enabled for full audit trail of AI-assisted development
