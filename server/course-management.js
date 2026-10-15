export function validateCourse(data){
  const name=String(data.name||'').trim(),code=String(data.code||'').trim().toUpperCase(),alias=String(data.alias||'').trim();
  const duration=Number(data.durationYears),intake=Number(data.intake);
  if(!name||name.length>150||!code||code.length>30||!alias||alias.length>100||!Number.isFinite(duration)||duration<=0||duration>10||!Number.isInteger(duration*2))throw new Error('Enter Course Name, Code, Alias and a valid duration in years.');
  const batchName=String(data.batchName||'').trim(),batchAlias=String(data.batchAlias||'').trim(),sectionName=String(data.sectionName||'').trim();
  const validDate=value=>/^\d{4}-\d{2}-\d{2}$/.test(value||'')&&!Number.isNaN(Date.parse(value))&&new Date(value).toISOString().slice(0,10)===value;
  if(!batchName||batchName.length>100||!batchAlias||batchAlias.length>50||!sectionName||sectionName.length>100||!Number.isInteger(intake)||intake<=0||!validDate(data.startDate)||!validDate(data.endDate)||data.endDate<=data.startDate)throw new Error('Complete the initial Batch and Section fields. End Date must follow Start Date, and Intake must be a positive whole number.');
  return {name,code,alias,duration,intake,batchName,batchAlias,sectionName,startDate:data.startDate,endDate:data.endDate};
}
export function registerCourseRoutes(app,pool,authenticate){
  app.get('/api/courses',authenticate,async(_req,res)=>{
    try{const result=await pool.query('SELECT programme_id AS id,programme_name AS name,programme_code AS code,programme_alias AS alias,duration_years,is_active FROM programmes ORDER BY programme_name');res.json({ok:true,courses:result.rows});}catch{res.status(500).json({ok:false,message:'Unable to load courses.'});}
  });
  app.put('/api/courses/:id',authenticate,async(req,res)=>{
    if(!['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role))return res.status(403).json({ok:false,message:'Only administrators can edit courses.'});
    const id=Number(req.params.id),name=String(req.body.name||'').trim(),code=String(req.body.code||'').trim().toUpperCase(),alias=String(req.body.alias||'').trim();
    if(!Number.isSafeInteger(id)||id<=0||!name||name.length>150||!code||code.length>30||!alias||alias.length>100||typeof req.body.isActive!=='boolean')return res.status(400).json({ok:false,message:'Enter a valid Course Name, Code, Alias and Status.'});
    try{
      if((await pool.query('SELECT 1 FROM programmes WHERE UPPER(programme_code)=$1 AND programme_id<>$2',[code,id])).rowCount)return res.status(409).json({ok:false,message:'Course Code already exists.'});
      const result=await pool.query("UPDATE programmes SET programme_name=$1,programme_code=$2,programme_alias=$3,is_active=$4,status=$5 WHERE programme_id=$6 RETURNING programme_id",[name,code,alias,req.body.isActive,req.body.isActive?'ACTIVE':'INACTIVE',id]);
      if(!result.rowCount)return res.status(404).json({ok:false,message:'Course not found.'});res.json({ok:true,message:'Course updated successfully.'});
    }catch{res.status(500).json({ok:false,message:'Unable to update course.'});}
  });
  app.post('/api/courses',authenticate,async(req,res)=>{
    if(!['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role))return res.status(403).json({ok:false,message:'Only administrators can add courses.'});
    let data;try{data=validateCourse(req.body);}catch(error){return res.status(400).json({ok:false,message:error.message});}
    let client;
    try{
      client=await pool.connect();await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['course:'+data.code]);
      if((await client.query('SELECT 1 FROM programmes WHERE UPPER(programme_code)=$1',[data.code])).rowCount)throw new Error('Course Code already exists.');
      const year=Number(data.startDate.slice(0,4));
      const academicYear=(await client.query('SELECT academic_year_id FROM academic_years WHERE EXTRACT(YEAR FROM start_date)=$1 ORDER BY academic_year_id LIMIT 1',[year])).rows[0];
      if(!academicYear)throw new Error(`Create Academic Year ${year}-${String(year+1).slice(-2)} before adding this course.`);
      const institution=(await client.query('SELECT institution_id FROM institutions WHERE is_active ORDER BY institution_id LIMIT 1')).rows[0];
      if(!institution)throw new Error('Create an active institution first.');
      let department=(await client.query('SELECT department_id FROM departments WHERE institution_id=$1 AND UPPER(department_code)=$2',[institution.institution_id,data.code])).rows[0];
      if(!department)department=(await client.query("INSERT INTO departments(institution_id,department_code,department_name,department_type,is_active) VALUES($1,$2,$3,'ACADEMIC',TRUE) RETURNING department_id",[institution.institution_id,data.code,data.name])).rows[0];
      const course=(await client.query(`INSERT INTO programmes(department_id,programme_code,programme_name,programme_alias,programme_level,programme_type,duration_years,total_semesters,intake_capacity,award_type,status,is_active)
        VALUES($1,$2,$3,$4,'UNDERGRADUATE','UNDERGRADUATE',$5,$6,$7,'DEGREE','ACTIVE',TRUE) RETURNING programme_id`,[department.department_id,data.code,data.name,data.alias,data.duration,data.duration*2,data.intake])).rows[0];
      let firstSemester;
      for(let number=1;number<=data.duration*2;number++){const semester=(await client.query('INSERT INTO semesters(programme_id,semester_number,semester_name,year_number,is_active) VALUES($1,$2,$3,$4,TRUE) RETURNING semester_id',[course.programme_id,number,'Semester '+number,Math.ceil(number/2)])).rows[0];if(number===1)firstSemester=semester;}
      const batch=(await client.query(`INSERT INTO admission_batches(programme_id,admission_year,batch_name,batch_alias,start_date,expected_end_date,approved_intake,lateral_entry_intake,status,is_active)
        VALUES($1,$2,$3,$4,$5,$6,$7,0,'ACTIVE',TRUE) RETURNING batch_id`,[course.programme_id,year,data.batchName,data.batchAlias,data.startDate,data.endDate,data.intake])).rows[0];
      let master=(await client.query('SELECT section_master_id FROM section_masters WHERE LOWER(section_master_name)=LOWER($1)',[data.sectionName])).rows[0];
      if(!master)master=(await client.query('INSERT INTO section_masters(section_master_code,section_master_name,is_active,created_by) VALUES($1,$2,TRUE,$3) RETURNING section_master_id',['SEC_'+course.programme_id,data.sectionName,req.auth.userId])).rows[0];
      let term=(await client.query('SELECT term_id FROM academic_terms WHERE academic_year_id=$1 ORDER BY term_id LIMIT 1',[academicYear.academic_year_id])).rows[0];
      if(!term)term=(await client.query("INSERT INTO academic_terms(academic_year_id,term_name,term_type,start_date,end_date,status) VALUES($1,'Semester 1','SEMESTER',$2,$3,'ACTIVE') RETURNING term_id",[academicYear.academic_year_id,data.startDate,data.endDate])).rows[0];
      const section=(await client.query('INSERT INTO sections(batch_id,semester_id,term_id,section_name,strength_limit,section_master_id,is_active) VALUES($1,$2,$3,$4,$5,$6,TRUE) RETURNING section_id',[batch.batch_id,firstSemester.semester_id,term.term_id,data.sectionName,data.intake,master.section_master_id])).rows[0];
      await client.query('INSERT INTO batch_section_assignments(batch_id,section_master_id,initial_section_id,intake,is_active) VALUES($1,$2,$3,$4,TRUE)',[batch.batch_id,master.section_master_id,section.section_id,data.intake]);
      await client.query('INSERT INTO course_initial_setup(course_id,batch_id,section_id) VALUES($1,$2,$3)',[course.programme_id,batch.batch_id,section.section_id]);
      await client.query('COMMIT');res.status(201).json({ok:true,id:course.programme_id,message:'Course, initial batch and section created successfully.'});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code==='23505'?409:400).json({ok:false,message:error.code==='23505'?'Course or section already exists.':error.message});}finally{client?.release();}
  });
}
