# Predict POT — Auto Config Generator Workflow

## Overview

This document defines the conversational workflow for converting a filled-out
Google Doc intake form into a ready-to-use `customer_config.json` file.

**Trigger:** Jonathan says something like "generate config for [customer]" or
"read the intake form for [customer]" and provides a Google Doc ID or link.

**Output:** A JSON config file saved to the workspace folder, with confidence
flags and a review summary.

---

## Step 1: Read the Google Doc

Use `read_file_content` with the provided Google Doc ID. The form is a native
Google Doc (v3, template ID: `1fdJPAO8y8Cp2P7R0z_kg1qc8sgAuQEBsZM4h54TFMRo`).

Parse the text by looking for each question marker (`Q1.` through `Q13.`) and
extracting the text between "Your answer:" and the next section divider or
question marker. Also extract:
- Company Name (after "Company Name:")
- Contact name (after "Your Name & Title:")
- Date (after "Date:")
- Q7 has two sub-fields: "Closed renewal date field:" and "Open/upcoming renewal date field:"
- Q6 has a sub-field: "If the field is NOT annual revenue..." for ARR transform

If any answer still contains `[enter here]` or is empty, flag it as unanswered.

---

## Step 2: Map Answers to Config Fields

### Direct Mappings (High Confidence)

| Intake Field            | Config Path                          | Notes                       |
|-------------------------|--------------------------------------|-----------------------------|
| Company Name            | `customer.name`                      | Verbatim                    |
| Contact Name            | _(informational only)_               | Note in review              |
| Date                    | `customer.analysis_date`             | Parse to YYYY-MM-DD         |
| Q1 (renewal object)     | `sfdc.objects.renewal_object`        | Verbatim; default "Opportunity" |
| Q7 closed date          | `sfdc.fields.close_date.field`       | Verbatim; default "CloseDate" |
| Q7 upcoming date        | `sfdc.fields.renewal_date.field`     | Verbatim; may = close_date  |

### Interpreted Mappings (Medium Confidence — Flag for Review)

These require translating natural language into SQL conditions.

| Intake Q | Config Path                              | Translation Logic                          |
|----------|------------------------------------------|--------------------------------------------|
| Q2       | `sfdc.filters.is_renewal.condition`      | See pattern table below                    |
| Q3       | `sfdc.filters.is_churn.condition`        | See pattern table below                    |
| Q4       | `sfdc.filters.is_renewal_won.condition`  | See pattern table below                    |
| Q5       | `sfdc.filters.is_open_renewal.condition` | See pattern table below                    |
| Q6       | `sfdc.fields.arr.field` + `.transform`   | Field name + optional transform expression |
| Q8       | `pendo.account_mapping.sfdc_match_field` | See pattern table below                    |

### Exclusion Mappings (Medium Confidence)

| Intake Q | Config Path                                      | Translation Logic              |
|----------|--------------------------------------------------|--------------------------------|
| Q9       | `sfdc.filters.exclude_conditions.conditions[]`   | Parse exclusion patterns       |
| Q10      | `sfdc.filters.exclude_conditions.conditions[]`   | Add `Amount > 0` if "yes"      |

### Informational Only (No Config Field)

| Intake Q | What to Do                                                          |
|----------|---------------------------------------------------------------------|
| Q11      | If < 12 months, flag WARNING: insufficient history                  |
| Q12      | If < 200 churns, flag WARNING: may not meet Predict minimum         |
| Q13      | Surface verbatim in review notes — may affect config decisions      |

---

## Step 3: SQL Condition Pattern Matching

When translating natural-language answers to SQL conditions, use these patterns:

### Q2 — is_renewal

| Customer Says                                  | SQL Condition                                          |
|------------------------------------------------|--------------------------------------------------------|
| "Record Type called 'Renewal'"                 | `RecordType.Name = 'Renewal'`                          |
| "Type field set to 'Renewal'"                  | `Type = 'Renewal'`                                     |
| "Type is 'Renewal' or 'Renewal - Auto'"        | `Type IN ('Renewal', 'Renewal - Auto')`                |
| "Custom field Opportunity_Type__c"             | `Opportunity_Type__c = '<value>'`                      |
| "RecordTypeId = '012XXX...'"                   | `RecordTypeId = '012XXX...'`                           |

### Q3 — is_churn

| Customer Says                                  | SQL Condition                                          |
|------------------------------------------------|--------------------------------------------------------|
| "Stage = Closed Lost"                          | `StageName = 'Closed Lost'`                            |
| "Stage is 'Churned' or 'Non-Renewal'"          | `StageName IN ('Churned', 'Non-Renewal')`              |
| "Checkbox field Churn__c"                      | `Churn__c = TRUE`                                      |
| "Renewal Outcome field = 'Churn'"              | `Renewal_Outcome__c = 'Churn'`                         |
| "IsWon = false and IsClosed = true"            | `IsWon = FALSE AND IsClosed = TRUE`                    |

### Q4 — is_renewal_won

| Customer Says                                  | SQL Condition                                          |
|------------------------------------------------|--------------------------------------------------------|
| "Stage = Closed Won"                           | `StageName = 'Closed Won'`                             |
| "Stage is 'Renewed'"                           | `StageName = 'Renewed'`                                |
| "Renewal Outcome = 'Renewed'"                  | `Renewal_Outcome__c IN ('Renewed', 'Expanded')`        |
| "IsWon = true"                                 | `IsWon = TRUE`                                         |

### Q5 — is_open_renewal

| Customer Says                                  | SQL Condition                                          |
|------------------------------------------------|--------------------------------------------------------|
| "Just open Opportunities"                      | `IsClosed = FALSE`                                     |
| "Stage is 'In Renewal' or 'Pending Renewal'"   | `StageName IN ('In Renewal', 'Pending Renewal')`       |
| "Pipeline stage 'Up for Renewal'"              | `StageName = 'Up for Renewal'`                         |
| "IsClosed = false"                             | `IsClosed = FALSE`                                     |

### Q6 — ARR field

| Customer Says                                  | Config Values                                          |
|------------------------------------------------|--------------------------------------------------------|
| "Amount (it represents annual value)"          | field: "Amount", transform: null                       |
| "ARR__c"                                       | field: "ARR__c", transform: null                       |
| "MRR__c and multiply by 12"                    | field: "MRR__c", transform: "MRR__c * 12"             |
| "Amount is total, Term is in months"           | field: "Amount", transform: "Amount / Contract_Term_Months__c * 12" |
| "Annual_Contract_Value__c"                     | field: "Annual_Contract_Value__c", transform: null     |

### Q8 — Pendo-SFDC mapping

| Customer Says                                  | Config Value (sfdc_match_field)                        |
|------------------------------------------------|--------------------------------------------------------|
| "Pendo uses Salesforce Account ID directly"    | `Account.Id`                                           |
| "Custom field Pendo_Account_ID__c"             | `Account.Pendo_Account_ID__c`                          |
| "External ID field"                            | `Account.External_ID__c` (flag for exact name)         |
| "Not sure"                                     | FLAG: needs follow-up with Pendo admin                 |

### Q9 — Exclusion conditions

Parse the answer for patterns like:
- "anything with 'Test'" → `LOWER(Account.Name) NOT LIKE '%test%'`
- "'Sandbox' in the account name" → `LOWER(Account.Name) NOT LIKE '%sandbox%'`
- "internal account 'Acme Internal'" → `Account.Name != 'Acme Internal'`
- "demo accounts" → `LOWER(Account.Name) NOT LIKE '%demo%'`

### Q10 — $0 amounts

- "Yes" or describes $0 records → add `Amount > 0` to exclude_conditions
- "No" or "Not that I know of" → no action

---

## Step 4: Generate Config JSON

Build the full config using `customer_config_template.json` as the base
structure. Fill in all mapped values. For fields not covered by the intake
form, use defaults:

- `customer.ce_name`: "Jonathan Rice"
- `customer.ce_email`: "jonathan.rice@pendo.io"
- `customer.sql_dialect`: "athena"
- `sfdc.objects.account_object`: "Account"
- `sfdc.fields.account_id`: "AccountId"
- `sfdc.fields.account_name`: "Account.Name"
- `sfdc.fields.opportunity_id`: "Id"
- `sfdc.fields.stage.field`: "StageName"
- `sfdc.filters.is_closed.condition`: "IsClosed = TRUE"
- `sfdc.time_windows`: { historical_months: 12, upcoming_months: 12 }
- `pendo.tables.*`: defaults (CE fills later)
- `pendo.columns.*`: defaults (CE fills later)
- `dashboard_overrides`: { conservative: 1.0, benchmark: 2.0 }

---

## Step 5: Review Summary

After generating the config, produce a review summary with three sections:

### ✅ High Confidence (no review needed)
List fields that were directly mapped from clear answers.

### ⚠️ Needs Review (flagged interpretations)
For each flagged field, show:
- The customer's original answer
- The SQL condition or value I generated
- Why it was flagged (ambiguous wording, multiple possible interpretations, etc.)
- Suggested alternative if applicable

### 🚨 Warnings
- Unanswered questions
- Q11 < 12 months history
- Q12 < 200 churns
- Q8 "not sure" responses
- Q13 unusual items that may need config adjustments

### CE Action Items
- Pendo table/column names to fill in (always — these are CE-provided)
- Any flagged fields to confirm
- Any follow-ups needed (e.g., Pendo admin contact)

---

## Step 6: Save Output

Save the generated config as:
`/sessions/laughing-funny-goodall/mnt/Predict POT - Biz Case/<customer_name>_config.json`

Present the review summary to Jonathan and wait for confirmation or edits
before considering the config final.
