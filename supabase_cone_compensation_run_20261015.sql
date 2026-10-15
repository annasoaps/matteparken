-- Engångskompensation Matteparken 2026-10-15.
-- 21 snabba upprepade köp (<8 sek), 11 elever, 1500 kottar.
-- Detta är goodwill, inte ett påstående om att alla köp var felaktiga.
-- HELA operationen avbryts och rullas tillbaka om kontrollsummor avviker.
DO $refund$
DECLARE
 v_candidates integer;
 v_students integer;
 v_amount integer;
 v_already integer;
 v_inserted integer;
 v_inserted_students integer;
 v_credited integer;
 v_updated integer;
BEGIN
 PERFORM pg_advisory_xact_lock(1510,20261015);
 WITH ordered AS (
   SELECT id,student_id,purchase_kind,item_id,price,purchased_at,
     lag(purchased_at) OVER (
       PARTITION BY student_id,purchase_kind,item_id
       ORDER BY purchased_at,id
     ) AS prev_purchase
   FROM public.student_cone_purchases
   WHERE purchased_at < '2026-10-15 15:13:00+00'::timestamptz
 ), candidates AS (
   SELECT * FROM ordered
   WHERE prev_purchase IS NOT NULL
     AND purchased_at - prev_purchase < interval '8 seconds'
 )
 SELECT count(*)::integer,count(distinct student_id)::integer,
        coalesce(sum(price),0)::integer
 INTO v_candidates,v_students,v_amount FROM candidates;

 IF (v_candidates,v_students,v_amount) IS DISTINCT FROM (21,11,1500) THEN
   RAISE EXCEPTION 'Avbrutet: annan urvalssumma %, %, %',
     v_candidates,v_students,v_amount;
 END IF;

 SELECT count(*) INTO v_already FROM public.student_cone_compensations
 WHERE batch_key='fast_repeats_goodwill_2026_10_15';
 IF v_already>0 THEN
   RAISE EXCEPTION 'Avbrutet: kompensationsomgången är redan bokförd';
 END IF;

 WITH ordered AS (
   SELECT id,student_id,purchase_kind,item_id,price,purchased_at,
     lag(purchased_at) OVER (
       PARTITION BY student_id,purchase_kind,item_id
       ORDER BY purchased_at,id
     ) AS prev_purchase
   FROM public.student_cone_purchases
   WHERE purchased_at < '2026-10-15 15:13:00+00'::timestamptz
 ), candidates AS (
   SELECT * FROM ordered
   WHERE prev_purchase IS NOT NULL
     AND purchased_at - prev_purchase < interval '8 seconds'
 ), credits AS (
   INSERT INTO public.student_cone_compensations
     (source_purchase_id,student_id,amount,batch_key,reason)
   SELECT id,student_id,price,'fast_repeats_goodwill_2026_10_15',
     'Engångskompensation vid snabbt upprepat köp; ej fastställt som felköp'
   FROM candidates
   RETURNING student_id,amount
 ), by_student AS (
   SELECT student_id,sum(amount)::integer AS amount
   FROM credits GROUP BY student_id
 ), updated_balances AS (
   UPDATE public.student_cones c
     SET balance=c.balance+bs.amount, updated_at=now()
     FROM by_student bs WHERE c.student_id=bs.student_id
     RETURNING c.student_id
 )
 SELECT (SELECT count(*) FROM credits),
        (SELECT count(distinct student_id) FROM credits),
        (SELECT coalesce(sum(amount),0) FROM credits),
        (SELECT count(*) FROM updated_balances)
 INTO v_inserted,v_inserted_students,v_credited,v_updated;

 IF (v_inserted,v_inserted_students,v_credited,v_updated)
    IS DISTINCT FROM (21,11,1500,11) THEN
   RAISE EXCEPTION 'Avbrutet: fel antal krediteringar %, %, %, %',
     v_inserted,v_inserted_students,v_credited,v_updated;
 END IF;
END
$refund$;