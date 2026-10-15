import {subjectMatchesAllocation} from './subject-allocation-scope.js';
export function registerClassTeacherSubjectSave(app,pool,authenticate){
 const save=async(req,res)=>{const d=req.body,id=req.params.id?Number(req.params.id):null,c=await pool.connect();try{
   const ids=[d.academicYearId,d.programmeId,d.batchId,d.semesterId,d.sectionId,d.employeeId,d.subjectId].map(Number),group=String(d.studentGroup||'').trim().toUpperCase();if(!ids.every(n=>Number.isSafeInteger(n)&&n>0)||!group||group.length>30||!['MAIN','ASSISTANT'].includes(d.teacherType))throw Error('Complete all required allocation fields.');
   await c.query('BEGIN');if(!await subjectMatchesAllocation(c,d))throw Error('Subject, Semester and Section must belong to the selected Course and Batch.');
   if(!(await c.query('SELECT 1 FROM admission_batches WHERE batch_id=$1 AND programme_id=$2',[ids[2],ids[1]])).rowCount)throw Error('Batch must belong to Course.');
   if(!(await c.query("SELECT 1 FROM employees WHERE employee_id=$1 AND UPPER(status)='ACTIVE'",[ids[5]])).rowCount)throw Error('Select an active teacher.');
   if(!(await c.query("SELECT 1 FROM subject_teacher_allocations WHERE academic_year_id=$1 AND batch_id=$2 AND semester_id=$3 AND section_id=$4 AND subject_master_id=$5 AND employee_id=$6 AND status='ACTIVE'",[ids[0],ids[2],ids[3],ids[4],ids[6],ids[5]])).rowCount)throw Error('Teacher must be actively assigned to this Subject, Batch, Semester and Section first.');
   const values=[ids[0],ids[1],ids[2],ids[3],ids[4],group,ids[5],d.teacherType,ids[6],req.auth.userId];
   const result=id?await c.query(`UPDATE class_teacher_allocations SET academic_year_id=$1,programme_id=$2,batch_id=$3,semester_id=$4,section_id=$5,student_group=$6,employee_id=$7,teacher_type=$8,subject_master_id=$9,status='ACTIVE',updated_by=$10,updated_at=NOW() WHERE class_teacher_allocation_id=$11 RETURNING class_teacher_allocation_id`,[...values,id]):await c.query(`INSERT INTO class_teacher_allocations(academic_year_id,programme_id,batch_id,semester_id,section_id,student_group,employee_id,teacher_type,subject_master_id,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING class_teacher_allocation_id`,values);
   if(!result.rowCount)throw Error('Allocation not found.');await c.query('COMMIT');res.status(id?200:201).json({ok:true,message:id?'Allocation updated successfully.':'Teacher allotted successfully.'});
 }catch(error){await c.query('ROLLBACK');res.status(error.code==='23505'?409:400).json({ok:false,message:error.code==='23505'?'This subject and teacher type are already allocated to the class and group.':error.message});}finally{c.release();}};
 app.post('/api/class-teacher-allocations',authenticate,save);app.put('/api/class-teacher-allocations/:id',authenticate,save);
}
