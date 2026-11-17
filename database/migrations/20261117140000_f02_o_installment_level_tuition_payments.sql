-- Add installment-level balances while preserving historical invoices and receipts.
CREATE TABLE IF NOT EXISTS invoice_installments (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE RESTRICT,
 installment_number SMALLINT NOT NULL CHECK (installment_number BETWEEN 1 AND 3),
 label VARCHAR(150),
 due_amount NUMERIC(12,2) NOT NULL CHECK (due_amount >= 0),
 reduction_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (reduction_amount >= 0 AND reduction_amount <= due_amount),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 UNIQUE(invoice_id, installment_number)
);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS installment_id UUID;
ALTER TABLE payments ADD CONSTRAINT payments_installment_fk
 FOREIGN KEY (installment_id) REFERENCES invoice_installments(id) ON DELETE RESTRICT;
INSERT INTO invoice_installments(invoice_id, installment_number, label, due_amount, reduction_amount)
SELECT i.id, 1, 'Situation antérieure (historique)', i.amount, i.reduction
FROM invoices i
WHERE NOT EXISTS (SELECT 1 FROM invoice_installments ii WHERE ii.invoice_id=i.id);
UPDATE payments p SET installment_id=ii.id
FROM invoice_installments ii
WHERE ii.invoice_id=p.invoice_id AND ii.installment_number=1 AND p.installment_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_invoice_installments_invoice ON invoice_installments(invoice_id, installment_number);
CREATE INDEX IF NOT EXISTS idx_payments_installment ON payments(installment_id);
