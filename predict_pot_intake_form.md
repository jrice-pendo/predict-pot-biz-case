# Pendo Predict — Data Intake Form

**Thanks for connecting with us!** To build your personalized Predict analysis, we need to understand how your Salesforce is set up. This should take about 10 minutes — just answer each question below. If you're unsure about any answer, put your best guess and we'll verify it together.

---

## Your Info

**Company Name:**

**Your Name & Title:**

**Date:**

---

## Section 1: Renewals

We need to understand how your team tracks renewal outcomes in Salesforce.

---

**Q1. Where do you track renewals in Salesforce — on the standard Opportunity object, or a custom object?**

> _Common answers: "Opportunity", "Renewal__c", "Subscription__c"_

**Your answer:**


---

**Q2. How do you distinguish a renewal from new business or an upsell? Is it a Record Type, a picklist value, or something else?**

> _Common answers:_
> - _"We use a Record Type called 'Renewal'"_
> - _"There's a Type field set to 'Renewal' or 'Renewal - Auto'"_
> - _"We have a custom field called Opportunity_Type__c"_

**Your answer:**


**To verify:** _Go to any closed renewal Opportunity in SFDC. What Record Type or Type value is shown?_

---

**Q3. When a customer churns (doesn't renew), what does that look like in Salesforce? What stage name or field value indicates a lost renewal?**

> _Common answers:_
> - _"Stage = Closed Lost"_
> - _"Stage is 'Churned' or 'Non-Renewal'"_
> - _"We have a checkbox field called Churn__c"_
> - _"The Renewal Outcome field is set to 'Churn'"_

**Your answer:**


**To verify:** _Find a customer who churned in the last year. What stage or field value is on that Opportunity?_

---

**Q4. And for a successful renewal — what stage or value indicates the customer renewed?**

> _Common answers:_
> - _"Stage = Closed Won"_
> - _"Stage is 'Renewed' or 'Closed - Renewed'"_
> - _"Renewal Outcome = 'Renewed'"_

**Your answer:**


---

**Q5. For upcoming renewals that haven't been decided yet, how do you identify those? Is it just that the Opportunity is still open, or is there a specific stage?**

> _Common answers:_
> - _"They're just open Opportunities (IsClosed = false)"_
> - _"Stage is 'In Renewal' or 'Pending Renewal'"_
> - _"We use a pipeline stage called 'Up for Renewal'"_

**Your answer:**


---

## Section 2: Revenue & Dates

We need to know which fields hold your revenue data and key dates.

---

**Q6. What field holds the annual recurring revenue (ARR) on your renewal records? If it's not labeled "ARR," what field represents the annual value of the contract?**

> _Common answers:_
> - _"Amount (it represents the annual value)"_
> - _"ARR__c — it's a custom field"_
> - _"We use MRR__c and multiply by 12 for annual"_
> - _"Annual_Contract_Value__c"_
> - _"We don't have an ARR field — Amount is the total contract value and Term is in months"_

**Your answer:**


**To verify:** _Pick any renewal Opportunity. Does the value in this field represent one year of revenue? If not, how is it calculated?_

---

**Q7. What date field records when a renewal closed (was decided)? And for open renewals, what date field shows when they're expected to close?**

> _For closed renewals, the answer is usually "CloseDate." For open renewals, it might be the same field or a different one like "Renewal_Due_Date__c" or "Contract_End_Date__c."_

**Closed renewal date field:**

**Open/upcoming renewal date field:**

---

## Section 3: Pendo Integration

We need to understand how Pendo accounts connect to your Salesforce accounts.

---

**Q8. How are your Pendo accounts linked to Salesforce accounts? Does Pendo use your Salesforce Account ID, or is there a shared ID field?**

> _Common answers:_
> - _"Pendo uses our Salesforce Account ID directly"_
> - _"We have a custom field on Account called Pendo_Account_ID__c"_
> - _"They're linked by an external ID field"_
> - _"I'm not sure — our Pendo admin would know"_

**Your answer:**


**If you're not sure,** that's fine — just let us know who on your team manages Pendo and we can follow up with them.

---

## Section 4: Data Quality

These help us make sure the analysis is accurate. Quick yes/no answers are fine.

---

**Q9. Are there any test accounts, sandbox data, or internal accounts in your Salesforce that we should exclude from the analysis?**

> _Example: "Yes — anything with 'Test' or 'Sandbox' in the account name, and our internal account 'Acme Internal.'"_

**Your answer:**


---

**Q10. Do you have any renewal records with $0 amounts or missing amounts that should be excluded?**

**Your answer:**


---

**Q11. Roughly how long have you been using your current Salesforce setup for tracking renewals? (We need at least 12 months of history.)**

> _Common answers: "About 2 years", "Since 2023", "We migrated to this SFDC instance 18 months ago"_

**Your answer:**


---

**Q12. Has your team tracked at least 200 churned accounts in Salesforce? (Doesn't need to be exact — a rough sense is fine.)**

> _This helps us know if there's enough data to train a predictive model._

**Your answer:**


---

## Section 5: Anything Else

**Q13. Is there anything unusual about how your team tracks renewals that we should know about? For example: multi-year contracts, separate objects for downsells, recent SFDC migrations, multiple currencies, etc.**

**Your answer:**


---

## What Happens Next

Once we have your answers, we'll:

1. **Connect to your Salesforce** and validate everything against your actual data
2. **Run our analysis** — data hygiene checks, renewal trends, churn patterns, and product usage
3. **Build your personalized Predict dashboard** showing exactly what's at stake and what Predict can deliver

This typically takes 1–2 business days after we receive your responses.

---

_Questions? Reach out to your Pendo contact or email predict@pendo.io._
