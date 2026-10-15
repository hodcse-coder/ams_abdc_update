export const definedSemesterSectionsSql=`INSERT INTO sections
  (batch_id,semester_id,term_id,section_name,strength_limit,section_master_id,is_active)
SELECT d.programme_batch_id,d.semester_id,initial.term_id,sm.section_master_name,a.intake,a.section_master_id,TRUE
FROM programme_semester_definitions d
JOIN semesters se ON se.semester_id=d.semester_id AND se.programme_id=d.course_id AND se.is_active=TRUE
JOIN admission_batches b ON b.batch_id=d.programme_batch_id AND b.programme_id=d.course_id AND b.is_active=TRUE
JOIN batch_section_assignments a ON a.batch_id=d.programme_batch_id AND a.is_active=TRUE
JOIN section_masters sm ON sm.section_master_id=a.section_master_id AND sm.is_active=TRUE
JOIN sections initial ON initial.section_id=a.initial_section_id AND initial.is_active=TRUE
WHERE d.is_active=TRUE AND d.class_type='SECTION'
  AND NOT EXISTS(SELECT 1 FROM sections s WHERE s.batch_id=d.programme_batch_id AND s.semester_id=d.semester_id AND s.section_master_id=a.section_master_id)
ON CONFLICT DO NOTHING`;
