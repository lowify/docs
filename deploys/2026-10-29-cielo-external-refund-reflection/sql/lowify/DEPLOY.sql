ALTER TABLE sales_refund
    ADD UNIQUE KEY uq_sales_refund_banking_refund_id (banking_refund_id);
