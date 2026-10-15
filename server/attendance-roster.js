// Section records are semester-specific; the section master identifies the class within a batch.
export const attendanceRosterSql=`SELECT st.student_id AS id,
 COALESCE(NULLIF(st.registration_number,''),NULLIF(st.registration_no,''),st.student_code) AS code,
 TRIM(CONCAT_WS(' ',st.first_name,st.middle_name,st.last_name)) AS name
 FROM sections target JOIN admission_batches b ON b.batch_id=target.batch_id
 JOIN students st ON st.batch_id=target.batch_id AND st.programme_id=b.programme_id
 LEFT JOIN sections current_section ON current_section.section_id=st.section_id
 WHERE target.section_id=$1 AND target.is_active=TRUE AND st.is_active=TRUE AND COALESCE(st.is_deleted,FALSE)=FALSE
 AND (st.section_id=target.section_id OR (target.section_master_id IS NOT NULL AND current_section.section_master_id=target.section_master_id AND current_section.batch_id=target.batch_id))
 ORDER BY COALESCE(NULLIF(st.roll_number,''),NULLIF(st.roll_no,''),st.registration_number,st.student_code),st.student_id`;
