# DA24B051 — DBMS Assignment 2

SQLite-based query optimisation, execution-plan analysis, and transaction concurrency experiments.

## Repository Contents

| File | Description |
|---|---|
| `README.md` | Project overview and usage |
| `data_generator.py` | Synthetic data generation |
| `queries.sql` | Assignment queries |
| `indexes.sql` | Index definitions for query optimisation |
| `plan_analysis.md` | Execution plans, cost analysis, and optimisation results |
| `task3_queries.sql` | Join queries and cost analysis |
| `task4_pushdown.sql` | Predicate pushdown experiments |
| `transactions.sql` | Transaction-related SQL |
| `concurrency_demo.sql` | Transaction isolation and lost-update experiments, with comments explaining what to execute in each connection |

## Experiments

- **Query optimisation:** Compare SQLite execution plans before and after adding indexes.
- **Join analysis:** Examine join plans, intermediate cardinalities, and theoretical costs.
- **Predicate pushdown:** Compare equivalent query formulations and execution behaviour.
- **Concurrency:** Demonstrate transaction isolation, lost updates, and write-locking behaviour.

## Tools

- SQLite
- DBeaver
- SQL and `EXPLAIN QUERY PLAN`

## Notes

- Follow the inline comments in `concurrency_demo.sql` for the execution order and the steps to run in separate database connections.
- Execution times are environment-dependent. Performance conclusions are based on observed query plans, result correctness, and measured timings.
