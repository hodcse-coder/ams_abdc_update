// Only assign an unassigned student when the batch has one unambiguous active section.
export const studentSectionSyncSql=`WITH eligible AS (
  SELECT st.student_id,MIN(s.section_id) AS section_id,MIN(s.semester_id) AS semester_id
  FROM students st
  JOIN batch_section_assignments a ON a.batch_id=st.batch_id AND a.is_active=TRUE
  JOIN sections s ON s.section_id=a.initial_section_id AND s.batch_id=st.batch_id AND s.is_active=TRUE
  JOIN semesters se ON se.semester_id=s.semester_id AND se.programme_id=st.programme_id
  WHERE st.section_id IS NULL AND COALESCE(st.is_deleted,FALSE)=FALSE
    AND (st.semester_id IS NULL OR st.semester_id=s.semester_id)
  GROUP BY st.student_id HAVING COUNT(DISTINCT s.section_id)=1
)
UPDATE students st SET section_id=e.section_id,semester_id=COALESCE(st.semester_id,e.semester_id),
  student_profile_details=st.student_profile_details||jsonb_build_object('sectionId',e.section_id::text,'semesterId',e.semester_id::text),updated_at=NOW()
FROM eligible e WHERE st.student_id=e.student_id`;
