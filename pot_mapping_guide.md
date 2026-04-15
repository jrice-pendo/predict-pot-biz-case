# Pendo Predict POT — Customer Mapping Guide

## Overview

This guide walks through the process of configuring the POT dashboard for a new customer. The goal is to map their specific Salesforce and Pendo schema to the standardized query templates, so the dashboard populates with their real data.

**Time to complete:** 10–15 minutes per customer (faster after the first few).

**Files in this kit:**

| File | Purpose |
|---|---|
| `customer_config_template.json` | Schema mapping template — copy and fill per customer |
| `query_templates.sql` | 10 parameterized queries that feed the dashboard |
| `predict_pot_dashboard.html` | The interactive dashboard with `{{PLACEHOLDER}}` variables |
| `pot_mapping_guide.md` | This guide |

---

## Step 1: Copy the Config Template

Copy `customer_config_template.json` and rename it for the customer:

```
customer_config_acme.json
```

Fill in the `customer` section (name, CE, date, SQL dialect).

---

## Step 2: Map the Renewal Object

Most customers track renewals on the standard **Opportunity** object, but some use custom objects. Ask:

> "Where do you track renewal outcomes in Salesforce? Is it the standard Opportunity object, or a custom object like `Renewal__c`?"

Set `sfdc.objects.renewal_object` accordingly.

---

## Step 3: Map the Key Fields

For each field below, you need the customer's actual SFDC field API name. If you have access to their SFDC, you can discover these. Otherwise, ask the CE or customer.

| Concept | Config Key | Question to Ask | Common Answers |
|---|---|---|---|
| **ARR** | `sfdc.fields.arr` | "Which field holds the annual recurring revenue on your renewal records?" | `Amount`, `ARR__c`, `Annual_Contract_Value__c`, `MRR__c * 12` |
| **Close Date** | `sfdc.fields.close_date` | "Which date field records when the renewal was decided?" | `CloseDate`, `Renewal_Close_Date__c` |
| **Renewal Date** | `sfdc.fields.renewal_date` | "For open renewals, which date field indicates when they're expected to close?" | `CloseDate`, `Renewal_Due_Date__c`, `Contract_End_Date__c` |
| **Stage** | `sfdc.fields.stage` | "What field tracks the outcome stage of a renewal?" | `StageName`, `Renewal_Stage__c` |

### Handling ARR Edge Cases

ARR is the trickiest field because it's calculated differently everywhere:

- **Simple:** A single field like `Amount` or `ARR__c` holds the annualized value.
- **Calculated:** `Amount / Contract_Term_Months__c * 12` — need to compute it.
- **On Account:** `Account.ARR__c` — lives on the Account object, not Opportunity. Requires a JOIN.
- **MRR-based:** `MRR__c * 12` — stored as monthly, needs multiplication.

If calculated, put the expression in `sfdc.fields.arr.transform`.

---

## Step 4: Map the Filters

This is where customers vary the most. You need SQL conditions for each concept:

### 4a: What Is a Renewal?

> "How do you distinguish renewal opportunities from new business, upsells, etc.?"

| Pattern | Example Condition |
|---|---|
| Record Type | `RecordType.Name = 'Renewal'` |
| Type picklist | `Type = 'Renewal'` |
| Custom field | `Opportunity_Type__c IN ('Renewal', 'Renewal - Auto')` |
| Stage prefix | `StageName LIKE 'Renewal%'` |

### 4b: What Is a Churn?

> "When a renewal is lost, what does that look like in Salesforce? What stage or field indicates churn?"

| Pattern | Example Condition |
|---|---|
| Stage name | `StageName = 'Closed Lost'` |
| Multiple stages | `StageName IN ('Closed Lost', 'Churned', 'Non-Renewal')` |
| Custom field | `Churn__c = TRUE` |
| Outcome field | `Renewal_Outcome__c = 'Churn'` |

### 4c: What Is a Successful Renewal?

> "And a successful renewal — is that just Closed Won, or do you have other stages like 'Renewed' or 'Expanded'?"

### 4d: What Is an Open Renewal?

> "For upcoming renewals, do you use IsClosed = FALSE, or is there a specific stage for pipeline renewals?"

### 4e: Exclusions

> "Are there any records we should exclude? Test accounts, $0 placeholder opps, internal accounts?"

---

## Step 5: Map the Pendo Connection

> "How does Pendo identify accounts? Do Pendo subscription IDs match your Salesforce Account IDs, or is there a custom field that links them?"

| Pattern | Config |
|---|---|
| Pendo uses SFDC Account ID directly | `sfdc_match_field: "Account.Id"` |
| Custom field on Account | `sfdc_match_field: "Account.Pendo_Account_ID__c"` |
| External shared ID | `sfdc_match_field: "Account.External_ID__c"` |

---

## Step 6: Generate the Queries

Once the config is filled out, substitute the values into `query_templates.sql`. For each `{{PLACEHOLDER}}`, replace with the customer-specific value from the config.

Run the queries in order (1–10). Each query's output maps to specific dashboard fields documented in the SQL comments.

---

## Step 7: Populate the Dashboard

Take the query outputs and replace the `{{PLACEHOLDER}}` values in `predict_pot_dashboard.html`. Also update the `DATA` JavaScript object at the bottom of the HTML with the monthly time-series data from Queries 4, 5, 7, and 10.

---

## Common Patterns by Customer Segment

Over time, you'll notice patterns. Here are a few to watch for:

**Enterprise SaaS (large, mature SFDC)**
- Usually have a dedicated `Renewal` Record Type on Opportunity
- ARR is often a custom field (`ARR__c` or `Annual_Value__c`)
- Multiple churn stages (Churned, Non-Renewal, Downgrade to $0)
- Clean Pendo-to-SFDC mapping via custom ID field

**Mid-Market SaaS (simpler SFDC)**
- Renewals identified by `Type = 'Renewal'` or just by stage
- ARR = `Amount` (assuming 1-year contracts)
- Churn = `Closed Lost` (single stage)
- Pendo mapping may use Account ID directly

**PLG / Usage-Based (non-traditional renewals)**
- May not have formal renewal Opportunities at all
- Churn tracked via subscription status, not Opportunity stage
- ARR may need to be pulled from a billing system, not SFDC
- Heavy Pendo data but sparse CRM data

---

## Troubleshooting

**"The churn count seems too low"**
- Check if downsells are tracked separately from full churns
- Check if some churns are logged as "Closed Won" with $0 amount
- Verify the renewal filter isn't too restrictive (missing auto-renewals)

**"ARR numbers don't match what the customer expects"**
- Confirm whether the field is annual or monthly
- Check for multi-year contracts inflating the total
- Verify currency — some customers have multi-currency SFDC orgs

**"Pendo match rate is near 0%"**
- The ID fields don't align — check if Pendo uses a different identifier
- Try matching on domain/company name as a fallback diagnostic

**"Data window is less than 12 months"**
- Customer may have migrated CRM recently
- Check if historical data was imported with correct dates
- May need to lower the threshold and note it in the dashboard
