export function validateBatch(data={}){
  const programmeId=Number(data.programmeId),name=String(data.name||'').trim(),alias=String(data.alias||'').trim();
  const validDate=value=>/^\d{4}-\d{2}-\d{2}$/.test(value||'')&&!Number.isNaN(Date.parse(value))&&new Date(value).toISOString().slice(0,10)===value;
  if(!Number.isSafeInteger(programmeId)||programmeId<=0||!name||name.length>100||!alias||alias.length>50||!validDate(data.startDate)||!validDate(data.endDate)||data.endDate<=data.startDate||typeof data.isActive!=='boolean')throw new Error('Enter Batch Name, Course, Alias and valid dates. End Date must follow Start Date.');
  return {programmeId,name,alias,startDate:data.startDate,endDate:data.endDate,isActive:data.isActive,year:Number(data.startDate.slice(0,4))};
}
export function registerBatchRoutes(app,pool,authenticate){
  const admin=(req,res,next)=>['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role)?next():res.status(403).json({ok:false,message:'Only administrators can change batches.'});
  app.get('/api/course-batches',authenticate,async(_req,res)=>{
    try{const [courses,batches]=await Promise.all([
      pool.query('SELECT programme_id AS id,programme_code AS code,programme_name AS name,is_active FROM programmes ORDER BY programme_code'),
      pool.query(`SELECT b.batch_id AS id,b.programme_id,b.batch_name AS name,b.batch_alias AS alias,b.start_date::text,b.expected_end_date::text AS end_date,b.is_active,p.programme_code,p.programme_name,
        COALESCE(s.annual_survey_eligible,FALSE) AS annual_survey_eligible,COALESCE(s.exit_survey_eligible,FALSE) AS exit_survey_eligible
        FROM admission_batches b JOIN programmes p ON p.programme_id=b.programme_id LEFT JOIN batch_survey_settings s ON s.batch_id=b.batch_id ORDER BY b.start_date DESC,b.batch_name`)
    ]);res.json({ok:true,courses:courses.rows,batches:batches.rows});}catch{res.status(500).json({ok:false,message:'Unable to load batches.'});}
  });
  const save=async(req,res)=>{
    let data;try{data=validateBatch(req.body);}catch(error){return res.status(400).json({ok:false,message:error.message});}
    const id=req.params.id?Number(req.params.id):null;if(req.params.id&&(!Number.isSafeInteger(id)||id<=0))return res.status(400).json({ok:false,message:'Invalid batch.'});
    let client;
    try{
      client=await pool.connect();await client.query('BEGIN');
      if(!(await client.query('SELECT 1 FROM programmes WHERE programme_id=$1 AND is_active',[data.programmeId])).rowCount)throw new Error('Select an active course.');
      if(id){
        const existing=(await client.query('SELECT programme_id FROM admission_batches WHERE batch_id=$1 FOR UPDATE',[id])).rows[0];
        if(!existing){await client.query('ROLLBACK');return res.status(404).json({ok:false,message:'Batch not found.'});}
        if(Number(existing.programme_id)!==data.programmeId)throw new Error('The Course of an existing batch cannot be changed.');
      }
      const values=[data.programmeId,data.name,data.alias,data.startDate,data.endDate,data.year,data.isActive,data.isActive?'ACTIVE':'INACTIVE'];
      const result=id?await client.query('UPDATE admission_batches SET programme_id=$1,batch_name=$2,batch_alias=$3,start_date=$4,expected_end_date=$5,admission_year=$6,is_active=$7,status=$8 WHERE batch_id=$9 RETURNING batch_id',[...values,id]):await client.query('INSERT INTO admission_batches(programme_id,batch_name,batch_alias,start_date,expected_end_date,admission_year,is_active,status) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING batch_id',values);
      await client.query('INSERT INTO batch_survey_settings(batch_id) VALUES($1) ON CONFLICT(batch_id) DO NOTHING',[result.rows[0].batch_id]);
      await client.query('COMMIT');res.status(id?200:201).json({ok:true,id:result.rows[0].batch_id,message:id?'Batch updated successfully.':'Batch created successfully.'});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code==='23505'?409:400).json({ok:false,message:error.code==='23505'?'A batch already exists for this Course and admission year.':error.message});}finally{client?.release();}
  };
  app.post('/api/course-batches',authenticate,admin,save);app.put('/api/course-batches/:id',authenticate,admin,save);
  app.put('/api/course-batches/:id/surveys',authenticate,admin,async(req,res)=>{
    const id=Number(req.params.id),{annualSurveyEligible,exitSurveyEligible}=req.body;
    if(!Number.isSafeInteger(id)||id<=0||typeof annualSurveyEligible!=='boolean'||typeof exitSurveyEligible!=='boolean')return res.status(400).json({ok:false,message:'Select valid survey eligibility values.'});
    try{const result=await pool.query(`INSERT INTO batch_survey_settings(batch_id,annual_survey_eligible,exit_survey_eligible) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM admission_batches WHERE batch_id=$1)
      ON CONFLICT(batch_id) DO UPDATE SET annual_survey_eligible=EXCLUDED.annual_survey_eligible,exit_survey_eligible=EXCLUDED.exit_survey_eligible,updated_at=NOW() RETURNING batch_id`,[id,annualSurveyEligible,exitSurveyEligible]);if(!result.rowCount)return res.status(404).json({ok:false,message:'Batch not found.'});res.json({ok:true,message:'Survey eligibility updated.'});}catch{res.status(500).json({ok:false,message:'Unable to update survey eligibility.'});}
  });
  app.delete('/api/course-batches/:id',authenticate,admin,async(req,res)=>{
    const id=Number(req.params.id);if(!Number.isSafeInteger(id)||id<=0)return res.status(400).json({ok:false,message:'Invalid batch.'});let client;
    try{
      client=await pool.connect();await client.query('BEGIN');
      if(!(await client.query('SELECT 1 FROM admission_batches WHERE batch_id=$1 FOR UPDATE',[id])).rowCount){await client.query('ROLLBACK');return res.status(404).json({ok:false,message:'Batch not found.'});}
      const dependencies=(await client.query(`SELECT n.nspname AS schema_name,t.relname AS table_name,a.attname AS column_name FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=c.conkey[1]
        WHERE c.contype='f' AND c.confrelid='public.admission_batches'::regclass AND t.relname NOT IN ('batch_survey_settings','course_initial_setup')`)).rows;
      const quote=value=>'"'+value.replaceAll('"','""')+'"';
      for(const item of dependencies){if((await client.query(`SELECT 1 FROM ${quote(item.schema_name)}.${quote(item.table_name)} WHERE ${quote(item.column_name)}=$1 LIMIT 1`,[id])).rowCount){await client.query('ROLLBACK');return res.status(409).json({ok:false,message:'This batch has student, section or academic records and cannot be deleted.'});}}
      await client.query('DELETE FROM admission_batches WHERE batch_id=$1',[id]);await client.query('COMMIT');res.json({ok:true,message:'Batch deleted successfully.'});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code==='23503'?409:500).json({ok:false,message:error.code==='23503'?'This batch is in use and cannot be deleted.':'Unable to delete batch.'});}finally{client?.release();}
  });
}
