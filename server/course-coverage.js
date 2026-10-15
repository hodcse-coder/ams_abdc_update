export const courseCoverageSql=`WITH topic_progress AS (
 SELECT lp.lesson_plan_id AS id,fsa.academic_year_id,fsa.programme_batch_id,fsa.semester_id,
 fsa.subject_id,fsa.faculty_employee_id,sm.subject_code,sm.subject_name,
 TRIM(CONCAT_WS(' ',e.first_name,e.middle_name,e.last_name)) AS faculty_name,
 GREATEST(COALESCE(t.planned_periods,0),0) AS planned,
 CASE WHEN LOWER(COALESCE(t.topic_status,''))='completed' THEN GREATEST(COALESCE(t.planned_periods,0),0)
 ELSE LEAST(GREATEST(COALESCE(t.planned_periods,0),0),held.periods) END AS completed
 FROM academics.lesson_plan_headers lp
 JOIN academics.faculty_subject_assignments fsa ON fsa.faculty_subject_assignment_id=lp.faculty_subject_assignment_id
 JOIN subject_masters sm ON sm.subject_master_id=fsa.subject_id
 JOIN employees e ON e.employee_id=fsa.faculty_employee_id
 LEFT JOIN academics.lesson_plan_topics t ON t.lesson_plan_id=lp.lesson_plan_id
 LEFT JOIN LATERAL(SELECT COUNT(*)::int AS periods FROM student_attendance_entries ae
   JOIN subject_teacher_allocations a ON a.subject_teacher_allocation_id=ae.subject_teacher_allocation_id
   WHERE a.academic_year_id=fsa.academic_year_id AND a.batch_id=fsa.programme_batch_id
   AND a.semester_id=fsa.semester_id AND a.section_id=fsa.programme_section_id
   AND a.subject_master_id=fsa.subject_id AND a.employee_id=fsa.faculty_employee_id
   AND LOWER(TRIM(ae.topic_covered))=LOWER(TRIM(t.topic_description))
   AND ae.attendance_date<=CURRENT_DATE) held ON TRUE
 WHERE ($1::bigint IS NULL OR (fsa.faculty_employee_id=$1 AND EXISTS(
   SELECT 1 FROM subject_teacher_allocations current_assignment
   WHERE current_assignment.employee_id=$1 AND current_assignment.subject_master_id=fsa.subject_id
   AND current_assignment.batch_id=fsa.programme_batch_id AND current_assignment.semester_id=fsa.semester_id
   AND current_assignment.section_id=fsa.programme_section_id AND current_assignment.status='ACTIVE')))
)
SELECT id,academic_year_id,programme_batch_id,semester_id,subject_id,faculty_employee_id,
 subject_code,subject_name,faculty_name,SUM(planned)::int AS planned_periods,SUM(completed)::int AS completed_periods,
 CASE WHEN SUM(planned)=0 THEN 0 ELSE ROUND(100.0*SUM(completed)/SUM(planned),2) END AS coverage
FROM topic_progress GROUP BY id,academic_year_id,programme_batch_id,semester_id,subject_id,
 faculty_employee_id,subject_code,subject_name,faculty_name ORDER BY subject_code,id`;
