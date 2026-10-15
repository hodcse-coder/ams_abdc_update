import {definedSemesterSectionsSql} from './defined-semester-sections.js';
import {studentSectionSyncSql} from './student-section-sync.js';
export function validateSectionAssignment(data={}){
  const batchId=Number(data.batchId),sectionMasterId=Number(data.sectionMasterId),intake=Number(data.intake);
  if(!Number.isSafeInteger(batchId)||batchId<=0||!Number.isSafeInteger(sectionMasterId)||sectionMasterId<=0||!Number.isSafeInteger(intake)||intake<=0||intake>2147483647||typeof data.isActive!=='boolean')throw new Error('Select Section and Section Batch, and enter a positive whole-number Intake.');
  return {batchId,sectionMasterId,intake,isActive:data.isActive};
}
export function registerSectionAssignmentRoutes(app,pool,authenticate){
  const admin=(req,res,next)=>['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role)?next():res.status(403).json({ok:false,message:'Only administrators can change section assignments.'});
  app.get('/api/batch-sections',authenticate,async(_req,res)=>{
    try{const [sections,batches,assignments]=await Promise.all([
      pool.query('SELECT section_master_id AS id,section_master_name AS name,is_active FROM section_masters ORDER BY section_master_name'),
      pool.query('SELECT b.batch_id AS id,b.batch_name AS name,b.is_active,p.programme_code FROM admission_batches b JOIN programmes p ON p.programme_id=b.programme_id ORDER BY b.admission_year DESC,b.batch_name'),
      pool.query(`SELECT a.assignment_id AS id,a.batch_id,a.section_master_id,a.intake,a.is_active,s.section_master_name AS section_name,b.batch_name,p.programme_code
        FROM batch_section_assignments a JOIN section_masters s ON s.section_master_id=a.section_master_id JOIN admission_batches b ON b.batch_id=a.batch_id JOIN programmes p ON p.programme_id=b.programme_id ORDER BY s.section_master_name,b.batch_name`)
    ]);res.json({ok:true,sections:sections.rows,batches:batches.rows,assignments:assignments.rows});}catch{res.status(500).json({ok:false,message:'Unable to load section assignments.'});}
  });
  const save=async(req,res)=>{
    let data;try{data=validateSectionAssignment(req.body);}catch(error){return res.status(400).json({ok:false,message:error.message});}
    const id=req.params.id?Number(req.params.id):null;if(req.params.id&&(!Number.isSafeInteger(id)||id<=0))return res.status(400).json({ok:false,message:'Invalid assignment.'});let client;
    try{
      client=await pool.connect();await client.query('BEGIN');
      const master=(await client.query('SELECT section_master_name FROM section_masters WHERE section_master_id=$1 AND is_active',[data.sectionMasterId])).rows[0];
      const batch=(await client.query('SELECT * FROM admission_batches WHERE batch_id=$1 AND is_active',[data.batchId])).rows[0];
      if(!master||!batch)throw new Error('Select an active Section and Batch.');
      if(id){
        const existing=(await client.query('SELECT * FROM batch_section_assignments WHERE assignment_id=$1 FOR UPDATE',[id])).rows[0];
        if(!existing){await client.query('ROLLBACK');return res.status(404).json({ok:false,message:'Assignment not found.'});}
        if(Number(existing.batch_id)!==data.batchId||Number(existing.section_master_id)!==data.sectionMasterId)throw new Error('The Section and Batch of an existing assignment cannot be changed.');
        await client.query('UPDATE batch_section_assignments SET intake=$1,is_active=$2,updated_at=NOW() WHERE assignment_id=$3',[data.intake,data.isActive,id]);
        await client.query('UPDATE sections SET strength_limit=$1,is_active=$2 WHERE batch_id=$3 AND section_master_id=$4',[data.intake,data.isActive,data.batchId,data.sectionMasterId]);
      }else{
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['batch-section:'+data.batchId+':'+data.sectionMasterId]);
        if((await client.query('SELECT 1 FROM batch_section_assignments WHERE batch_id=$1 AND section_master_id=$2',[data.batchId,data.sectionMasterId])).rowCount)throw new Error('This Section is already assigned to this Batch.');
        const semester=(await client.query('SELECT semester_id FROM semesters WHERE programme_id=$1 AND semester_number=1 AND is_active',[batch.programme_id])).rows[0];
        if(!semester)throw new Error('Create Semester 1 for this batch’s course first.');
        const year=(await client.query('SELECT academic_year_id FROM academic_years WHERE EXTRACT(YEAR FROM start_date)=$1 ORDER BY academic_year_id LIMIT 1',[batch.admission_year])).rows[0];
        if(!year)throw new Error('Create the Academic Year matching the Batch admission year first.');
        let term=(await client.query('SELECT term_id FROM academic_terms WHERE academic_year_id=$1 ORDER BY term_id LIMIT 1',[year.academic_year_id])).rows[0];
        if(!term){if(!batch.start_date||!batch.expected_end_date)throw new Error('Add Start Date and End Date to the Batch first.');term=(await client.query("INSERT INTO academic_terms(academic_year_id,term_name,term_type,start_date,end_date,status) VALUES($1,'Semester 1','SEMESTER',$2,$3,'ACTIVE') RETURNING term_id",[year.academic_year_id,batch.start_date,batch.expected_end_date])).rows[0];}
        const section=(await client.query(`INSERT INTO sections(batch_id,semester_id,term_id,section_name,strength_limit,section_master_id,is_active) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING section_id`,[data.batchId,semester.semester_id,term.term_id,master.section_master_name,data.intake,data.sectionMasterId,data.isActive])).rows[0];
        await client.query('INSERT INTO batch_section_assignments(batch_id,section_master_id,initial_section_id,intake,is_active) VALUES($1,$2,$3,$4,$5)',[data.batchId,data.sectionMasterId,section.section_id,data.intake,data.isActive]);
      }
      await client.query(definedSemesterSectionsSql);
      await client.query(studentSectionSyncSql);
      await client.query('COMMIT');res.status(id?200:201).json({ok:true,message:id?'Section assignment updated successfully.':'Section assigned successfully.'});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code==='23505'?409:400).json({ok:false,message:error.code==='23505'?'This Section already exists in the Batch.':error.message});}finally{client?.release();}
  };
  app.post('/api/batch-sections',authenticate,admin,save);app.put('/api/batch-sections/:id',authenticate,admin,save);
  app.delete('/api/batch-sections/:id',authenticate,admin,async(req,res)=>{
    const id=Number(req.params.id);if(!Number.isSafeInteger(id)||id<=0)return res.status(400).json({ok:false,message:'Invalid assignment.'});let client;
    try{
      client=await pool.connect();await client.query('BEGIN');const assignment=(await client.query('SELECT * FROM batch_section_assignments WHERE assignment_id=$1 FOR UPDATE',[id])).rows[0];
      if(!assignment){await client.query('ROLLBACK');return res.status(404).json({ok:false,message:'Assignment not found.'});}
      const ids=(await client.query('SELECT section_id FROM sections WHERE batch_id=$1 AND section_master_id=$2 FOR UPDATE',[assignment.batch_id,assignment.section_master_id])).rows.map(row=>row.section_id);
      const dependencies=(await client.query(`SELECT n.nspname AS schema_name,t.relname AS table_name,a.attname AS column_name FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=c.conkey[1]
        WHERE c.contype='f' AND c.confrelid='public.sections'::regclass AND t.relname NOT IN ('batch_section_assignments','course_initial_setup')`)).rows;
      const quote=value=>'"'+value.replaceAll('"','""')+'"';
      for(const dependency of dependencies)if((await client.query(`SELECT 1 FROM ${quote(dependency.schema_name)}.${quote(dependency.table_name)} WHERE ${quote(dependency.column_name)}=ANY($1::bigint[]) LIMIT 1`,[ids])).rowCount){await client.query('ROLLBACK');return res.status(409).json({ok:false,message:'This section has student or academic records and cannot be deleted.'});}
      await client.query('DELETE FROM batch_section_assignments WHERE assignment_id=$1',[id]);await client.query('DELETE FROM sections WHERE section_id=ANY($1::bigint[])',[ids]);await client.query('COMMIT');res.json({ok:true,message:'Section assignment deleted successfully.'});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code==='23503'?409:500).json({ok:false,message:error.code==='23503'?'This section is in use and cannot be deleted.':'Unable to delete section assignment.'});}finally{client?.release();}
  });
}
