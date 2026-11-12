-- Execute after database/schema.sql and every ordered migration.
-- Verifies the final PostgreSQL structure required by current application APIs.
DO $$
DECLARE missing_columns TEXT;
BEGIN
 SELECT string_agg(e.table_name || '.' || e.column_name, ', ' ORDER BY e.table_name,e.column_name)
 INTO missing_columns
 FROM (VALUES
 ('roles','id'),('roles','name'),('permissions','id'),('permissions','name'),
 ('role_permissions','role_id'),('role_permissions','permission_id'),
 ('users','id'),('users','username'),('users','password_hash'),('users','role_id'),('users','status'),
 ('school_years','id'),('school_years','label'),('school_years','start_date'),('school_years','end_date'),('school_years','status'),
 ('levels','id'),('levels','code'),('levels','name'),('classes','id'),('classes','code'),('classes','name'),('classes','level_id'),('classes','status'),
 ('subjects','id'),('subjects','code'),('subjects','name'),('subjects','coefficient'),('subjects','max_points'),('subjects','status'),
 ('students','id'),('students','matricule'),('students','last_name'),('students','first_name'),('students','profile_data'),('students','status'),
 ('enrollments','id'),('enrollments','student_id'),('enrollments','class_id'),('enrollments','school_year_id'),('enrollments','status'),
 ('grades','id'),('grades','enrollment_id'),('grades','subject_id'),('grades','grade'),('grades','assessment_number'),
 ('attendance','id'),('attendance','enrollment_id'),('attendance','attendance_date'),('attendance','status'),
 ('invoices','id'),('invoices','student_id'),('invoices','amount'),('invoices','status'),('invoices','school_year_id'),('invoices','reduction'),('invoices','reduction_reason'),
 ('payments','id'),('payments','invoice_id'),('payments','amount'),('payments','payment_date'),('payments','method'),
 ('staff','id'),('staff','first_name'),('staff','last_name'),('staff','function_name'),('staff','user_id'),('staff','class_name'),('staff','status'),
 ('user_teachers','user_id'),('user_teachers','teacher_id'),
 ('auth_login_attempts','key_hash'),('auth_login_attempts','failed_attempts'),('auth_login_attempts','first_failed_at'),('auth_login_attempts','blocked_until'),
 ('vacations','id'),('vacations','name'),('vacations','start_date'),('vacations','end_date'),('vacations','status'),
 ('result_carnets','id'),('result_carnets','enrollment_id'),('result_carnets','observation1'),('result_carnets','observation2'),('result_carnets','observation3'),
 ('finance_tariffs','id'),('finance_tariffs','school_year_id'),('finance_tariffs','class_id'),('finance_tariffs','amount'),('finance_tariffs','installment1_amount'),('finance_tariffs','installment2_amount'),('finance_tariffs','installment3_amount'),
 ('student_badges','id'),('student_badges','student_id'),('student_badges','created_by'),('student_badges','badge_data'),
 ('staff_audit_log','id'),('staff_audit_log','actor_user_id'),('staff_audit_log','staff_id'),('staff_audit_log','action'),('staff_audit_log','details'),
 ('expenses','id'),('expenses','school_year_id'),('expenses','description'),('expenses','amount'),('expenses','expense_date'),('expenses','created_by'),('expenses','legacy_id'),
 ('expense_reconciliation_audit','source_key_hash'),('expense_reconciliation_audit','source_year_label'),('expense_reconciliation_audit','source_legacy_id'),('expense_reconciliation_audit','target_school_year_id'),('expense_reconciliation_audit','expense_id'),('expense_reconciliation_audit','payload_hash'),('expense_reconciliation_audit','actor_user_id'),
 ('payroll_entries','id'),('payroll_entries','staff_id'),('payroll_entries','school_year_id'),('payroll_entries','payroll_month'),('payroll_entries','base_amount'),('payroll_entries','bonus_amount'),('payroll_entries','deduction_amount'),('payroll_entries','net_amount'),('payroll_entries','status'),('payroll_entries','legacy_source_key'),
 ('payroll_reconciliation_audit','source_key_hash'),('payroll_reconciliation_audit','source_staff_id'),('payroll_reconciliation_audit','target_staff_id'),('payroll_reconciliation_audit','school_year_id'),('payroll_reconciliation_audit','payroll_month'),('payroll_reconciliation_audit','payroll_entry_id'),('payroll_reconciliation_audit','actor_user_id'),
 ('whatsapp_consents','id'),('whatsapp_consents','parent_id'),('whatsapp_consents','purpose'),('whatsapp_consents','phone_e164'),('whatsapp_consents','status'),
 ('whatsapp_consent_audit','id'),('whatsapp_consent_audit','consent_id'),('whatsapp_consent_audit','parent_id'),('whatsapp_consent_audit','actor_user_id'),
 ('whatsapp_message_log','id'),('whatsapp_message_log','consent_id'),('whatsapp_message_log','idempotency_key'),('whatsapp_message_log','status'),('whatsapp_message_log','payload_sha256'),('whatsapp_message_log','initiated_by'),
 ('whatsapp_manual_preparations','id'),('whatsapp_manual_preparations','initiated_by'),('whatsapp_manual_preparations','parent_id'),('whatsapp_manual_preparations','consent_id'),('whatsapp_manual_preparations','phone_sha256'),('whatsapp_manual_preparations','message_sha256')
 ) AS e(table_name,column_name)
 WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns c
  WHERE c.table_schema='public' AND c.table_name=e.table_name AND c.column_name=e.column_name
 );
 IF missing_columns IS NOT NULL THEN
  RAISE EXCEPTION 'SCHEMA CONTRACT FAILED. Missing columns: %',missing_columns;
 END IF;
END $$;
SELECT 'SCHEMA CONTRACT: PASS' AS result;
