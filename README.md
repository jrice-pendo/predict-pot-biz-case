# Pendo Predict — Proof of Technology Kit

A self-contained toolkit for running Pendo Predict proof-of-technology engagements with prospects. It includes interactive dashboards, SQL query templates, configuration generators, and an ROI calculator — all designed to turn a prospect's Salesforce data into a compelling business case for Predict.

## Quick Start

1. Open any of the `.html` files in a browser — no build step or server required.
2. Start with the **POT Mapping Guide** (`pot_mapping_guide.md`) to understand the end-to-end workflow.
3. Use the **Data Intake Form** (`predict_pot_intake_form.md`) to collect a prospect's Salesforce schema details.
4. Generate a customer config and plug it into the dashboard.

## What's in the Kit

### Interactive Tools (open in browser)

| File | What it does |
|---|---|
| `predict_pot_dashboard.html` | The main POT dashboard — three sections covering data hygiene, exploratory analysis, and business case. Paste in query results and it renders charts and metrics. |
| `pot_generator.html` | Generates a customer-specific POT dashboard by combining query results with the config template. |
| `predict_roi_calculator.html` | Interactive ROI calculator that models the financial impact of Predict based on a prospect's renewal book. |

### Configuration & Queries

| File | What it does |
|---|---|
| `customer_config_template.json` | Schema mapping template — copy and fill out per customer to map their Salesforce fields to the standard queries. |
| `pendo_config.json` | A completed example config (Pendo's own data) for reference. |
| `techflow_solutions_config.json` | Another example config for a fictional company, useful for demos. |
| `query_templates.sql` | 10 parameterized SQL queries that feed the dashboard. Replace placeholders with values from the customer config. |
| `diagnostic_upcoming_arr.sql` | Diagnostic query for debugging upcoming renewal ARR calculations. |

### Documentation

| File | What it does |
|---|---|
| `pot_mapping_guide.md` | Step-by-step guide for configuring the dashboard for a new customer (10–15 min). |
| `predict_pot_intake_form.md` | Customer-facing intake form to collect Salesforce schema details before a POT. |
| `config_generator_workflow.md` | Documents the automated workflow for converting a completed intake form into a `customer_config.json`. |

## Requirements

- A modern web browser (Chrome, Firefox, Safari, Edge)
- That's it — everything runs client-side with no dependencies to install
