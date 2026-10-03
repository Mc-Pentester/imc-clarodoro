# ENV-18 - PostgreSQL Integrity Forensic Validation

Date : 2026-10-03 12:21:22

## Mode

READ-ONLY - SELECT and PostgreSQL catalogue queries only.

## PostgreSQL

PostgreSQL 18.4 on x86_64-windows, compiled by msvc-19.44.35227, 64-bit

## Results

| Check | Expected | Actual | Result |
|---|---|---|---|
| public tables exact set | 19 | 19 | PASS |
| Detail | | | missing=; extra= |
| UNIQUE constraints | 11 | 11 | PASS |
| PRIMARY KEY constraints | 19 | 19 | PASS |
| CHECK constraints | 23 | 23 | PASS |
| FOREIGN KEY constraints | 17 | 17 | PASS |
| application triggers | 0 | 0 | PASS |
| FOREIGN KEY ON DELETE RESTRICT | 17 | 17 | PASS |
| FOREIGN KEY ON DELETE CASCADE | 0 | 0 | PASS |
| FOREIGN KEY other delete actions | 0 | 0 | PASS |
| ordinary application indexes | 13 | 13 | PASS |
| partial unique enrollment index | 1 | 1 | PASS |
| users.password_hash | PRESENT | PRESENT | PASS |
| users.password | ABSENT | ABSENT | PASS |
| grades.enrollment_id | PRESENT | PRESENT | PASS |
| grades.student_id | ABSENT | ABSENT | PASS |
| grades.coefficient | ABSENT | ABSENT | PASS |
| attendance.enrollment_id | PRESENT | PRESENT | PASS |
| attendance.student_id | ABSENT | ABSENT | PASS |
| attendance.class_id | ABSENT | ABSENT | PASS |
| pgcrypto extension | 1 | 1 | PASS |

## Verdict

ENV-18 PASS

## Execution Safety

- Database : imc_clarodoro
- INSERT/UPDATE/DELETE : NO
- CREATE/ALTER/DROP : NO
- TRUNCATE : NO
- Database recreated : NO
