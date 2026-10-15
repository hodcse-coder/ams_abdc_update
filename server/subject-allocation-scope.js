export async function subjectMatchesAllocation(db,{batchId,semesterId,sectionId,subjectId}){
  const result=await db.query(`SELECT 1 FROM sections s
    JOIN admission_batches b ON b.batch_id=s.batch_id
    JOIN semesters se ON se.semester_id=s.semester_id
    JOIN subject_masters sm ON sm.programme_id=b.programme_id AND sm.semester_id=se.semester_id
    WHERE s.section_id=$1 AND b.batch_id=$2 AND se.semester_id=$3 AND sm.subject_master_id=$4
      AND b.programme_id=se.programme_id AND sm.is_active AND b.is_active AND se.is_active AND s.is_active`,
    [Number(sectionId),Number(batchId),Number(semesterId),Number(subjectId)]);
  return result.rowCount>0;
}
