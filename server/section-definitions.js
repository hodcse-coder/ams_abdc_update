export function validateSectionDefinition(data={}){
  const name=String(data.name||'').trim(),masterId=Number(data.masterId),admissionCourseId=Number(data.admissionCourseId),courseId=Number(data.courseId);
  if(!name||name.length>100||![masterId,admissionCourseId,courseId].every(id=>Number.isSafeInteger(id)&&id>0))throw new Error('Enter Section Name and select Section Master, Admission Form Course and Course.');
  return {name,masterId,admissionCourseId,courseId};
}
export function registerSectionDefinitionRoutes(app,pool,authenticate){
  const admin=(req,res,next)=>['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role)?next():res.status(403).json({ok:false,message:'Only administrators can change sections.'});
  app.get('/api/section-definitions',authenticate,async(_req,res)=>{
    try{const [masters,courses,sections]=await Promise.all([
      pool.query('SELECT section_master_id AS id,section_master_name AS name,is_active FROM section_masters ORDER BY section_master_name'),
      pool.query('SELECT programme_id AS id,programme_code AS code,programme_name AS name,is_active FROM programmes ORDER BY programme_code'),
      pool.query(`SELECT d.section_definition_id AS id,d.section_name AS name,d.section_master_id AS master_id,d.admission_course_id,d.course_id,m.section_master_name AS master_name,a.programme_code AS admission_course_code,p.programme_code AS course_code
        FROM section_definitions d JOIN section_masters m ON m.section_master_id=d.section_master_id JOIN programmes a ON a.programme_id=d.admission_course_id JOIN programmes p ON p.programme_id=d.course_id ORDER BY d.section_name,d.section_definition_id`)
    ]);res.json({ok:true,masters:masters.rows,courses:courses.rows,sections:sections.rows});}catch{res.status(500).json({ok:false,message:'Unable to load sections.'});}
  });
  const save=async(req,res)=>{
    let data;try{data=validateSectionDefinition(req.body);}catch(error){return res.status(400).json({ok:false,message:error.message});}
    const id=req.params.id?Number(req.params.id):null;if(req.params.id&&(!Number.isSafeInteger(id)||id<=0))return res.status(400).json({ok:false,message:'Invalid section.'});
    try{
      const valid=await pool.query(`SELECT 1 FROM section_masters m JOIN programmes a ON a.programme_id=$2 JOIN programmes p ON p.programme_id=$3 WHERE m.section_master_id=$1 AND m.is_active AND a.is_active AND p.is_active`,[data.masterId,data.admissionCourseId,data.courseId]);
      if(!valid.rowCount)return res.status(400).json({ok:false,message:'Select an active Section Master and active Courses.'});
      const values=[data.name,data.masterId,data.admissionCourseId,data.courseId];
      const result=id?await pool.query('UPDATE section_definitions SET section_name=$1,section_master_id=$2,admission_course_id=$3,course_id=$4,updated_at=NOW() WHERE section_definition_id=$5 RETURNING section_definition_id',[...values,id]):await pool.query('INSERT INTO section_definitions(section_name,section_master_id,admission_course_id,course_id,created_by) VALUES($1,$2,$3,$4,$5) RETURNING section_definition_id',[...values,req.auth.userId]);
      if(!result.rowCount)return res.status(404).json({ok:false,message:'Section not found.'});res.status(id?200:201).json({ok:true,id:result.rows[0].section_definition_id,message:id?'Section updated successfully.':'Section created successfully.'});
    }catch(error){res.status(error.code==='23505'?409:error.code==='23503'?400:500).json({ok:false,message:error.code==='23505'?'This Section Name and Course mapping already exists.':error.code==='23503'?'One of the selected records is invalid.':'Unable to save section.'});}
  };
  app.post('/api/section-definitions',authenticate,admin,save);app.put('/api/section-definitions/:id',authenticate,admin,save);
  app.delete('/api/section-definitions/:id',authenticate,admin,async(req,res)=>{
    const id=Number(req.params.id);if(!Number.isSafeInteger(id)||id<=0)return res.status(400).json({ok:false,message:'Invalid section.'});
    try{const result=await pool.query('DELETE FROM section_definitions WHERE section_definition_id=$1 RETURNING section_definition_id',[id]);if(!result.rowCount)return res.status(404).json({ok:false,message:'Section not found.'});res.json({ok:true,message:'Section deleted successfully.'});}catch(error){res.status(error.code==='23503'?409:500).json({ok:false,message:error.code==='23503'?'This section is in use and cannot be deleted.':'Unable to delete section.'});}
  });
}
