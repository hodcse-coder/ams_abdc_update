import {mergeSubjectRows} from '../shared/merge-subjects.js';
const adminRoles = ['ADMIN', 'SUPER_ADMIN', 'INSTITUTE_ADMIN'];
export function validateSubject(data) {
  const programmeId = Number(data.programmeId), semesterId = Number(data.semesterId);
  const code = String(data.code || '').trim().toUpperCase(), name = String(data.name || '').trim();
  if (!Number.isSafeInteger(programmeId) || programmeId <= 0 || !Number.isSafeInteger(semesterId) || semesterId <= 0 || !code || code.length > 30 || !name || name.length > 200 || typeof data.isActive !== 'boolean') throw new Error('Select Programme, Semester and Status, and enter a valid Subject Code and Name.');
  const components = Array.isArray(data.components) ? data.components : [];
  if (!components.length || components.length > 2) throw new Error('Select at least one subject type.');
  const seen = new Set();
  const normalized = components.map(item => {
    const type = item.type, raw = String(item.credit ?? '').trim(), credit = Number(raw);
    if (!['THEORY', 'PRACTICAL'].includes(type) || seen.has(type)) throw new Error('Select each subject type only once.');
    if (!/^\d+(\.\d{1,2})?$/.test(raw) || !Number.isFinite(credit) || credit < 0 || credit > 999.99) throw new Error('Each selected type needs a credit between 0 and 999.99, with up to two decimal places.');
    seen.add(type); return {type, credit};
  });
  return {programmeId, semesterId, code, name, isActive:data.isActive, components:normalized};
}

export function registerAcademicSubjectRoutes(app, pool, authenticate) {
  app.get('/api/academic-subjects', authenticate, async (_req, res) => {
    try {
      const [programmes, semesters, subjects] = await Promise.all([
        pool.query('SELECT programme_id AS id,programme_code AS code,programme_name AS name,is_active FROM programmes ORDER BY programme_code'),
        pool.query('SELECT semester_id AS id,programme_id,semester_number,semester_name AS name,is_active FROM semesters ORDER BY programme_id,semester_number'),
        pool.query(`SELECT sm.subject_master_id AS id,sm.programme_id,sm.semester_id,sm.subject_code AS code,sm.subject_name AS name,sm.is_active,
          p.programme_code,s.semester_name,s.semester_number,
          COALESCE(json_agg(json_build_object('type',c.subject_type,'credit',c.credit) ORDER BY c.subject_type DESC) FILTER (WHERE c.subject_component_id IS NOT NULL),'[]') AS components
          FROM subject_masters sm JOIN programmes p ON p.programme_id=sm.programme_id
          JOIN semesters s ON s.semester_id=sm.semester_id LEFT JOIN subject_components c ON c.subject_master_id=sm.subject_master_id
          GROUP BY sm.subject_master_id,p.programme_code,s.semester_name,s.semester_number ORDER BY p.programme_code,s.semester_number,sm.subject_code`)
      ]);
      res.json({ok:true,programmes:programmes.rows,semesters:semesters.rows,subjects:subjects.rows});
    } catch (error) { console.error('Academic subjects:',error.message); res.status(500).json({ok:false,message:'Unable to load subjects.'}); }
  });
  const admin = (req,res,next) => adminRoles.includes(req.auth.role) ? next() : res.status(403).json({ok:false,message:'Only administrators can change subjects.'});
  app.post('/api/academic-subjects/bulk',authenticate,admin,async(req,res)=>{
    let rows;
    try{
      if(!Array.isArray(req.body.rows)||!req.body.rows.length||req.body.rows.length>500)throw new Error('Upload between 1 and 500 subjects.');
      rows=mergeSubjectRows(req.body.rows.map((row,index)=>{
        try{
          const data=validateSubject(row);
          return data;
        }catch(error){throw new Error(`Row ${index+2}: ${error.message}`);}
      }));
    }catch(error){return res.status(400).json({ok:false,message:error.message});}
    let client;
    try{
      client=await pool.connect();await client.query('BEGIN');
      // Lock in code order to avoid deadlocks between simultaneous imports.
      for(const data of [...rows].sort((a,b)=>`${a.programmeId}:${a.semesterId}:${a.code}`.localeCompare(`${b.programmeId}:${b.semesterId}:${b.code}`))){
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`${data.programmeId}:${data.semesterId}:${data.code}`]);
      }
      for(let index=0;index<rows.length;index++){
        const data=rows[index];
        const programme=(await client.query(`SELECT p.department_id FROM programmes p JOIN semesters s ON s.programme_id=p.programme_id
          WHERE p.programme_id=$1 AND s.semester_id=$2 AND p.is_active AND s.is_active`,[data.programmeId,data.semesterId])).rows[0];
        if(!programme)throw new Error(`Row ${index+2}: select an active Programme and a Semester belonging to it.`);
        const existing=(await client.query('SELECT subject_master_id,subject_name,is_active FROM subject_masters WHERE programme_id=$1 AND semester_id=$2 AND UPPER(subject_code)=$3 FOR UPDATE',[data.programmeId,data.semesterId,data.code])).rows[0];
        let id=existing?.subject_master_id;
        if(existing){
          if(existing.subject_name.toLowerCase()!==data.name.toLowerCase()||existing.is_active!==data.isActive)throw new Error(`Row ${index+2}: ${data.code} has a different name or status. Use Edit to change it.`);
          const previous=(await client.query('SELECT subject_type FROM subject_components WHERE subject_master_id=$1',[id])).rows;
          data.components=data.components.filter(c=>!previous.some(p=>p.subject_type===c.type));
          if(!data.components.length)throw new Error(`Row ${index+2}: ${data.code} already has the selected subject types.`);
        }else{
          const component=data.components.find(c=>c.type==='THEORY')||data.components[0];
          id=(await client.query(`INSERT INTO subject_masters(programme_id,semester_id,subject_code,subject_name,is_active,department_id,subject_type,credit,created_by,subject_category)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'Professional Core') RETURNING subject_master_id`,[data.programmeId,data.semesterId,data.code,data.name,data.isActive,programme.department_id,component.type==='THEORY'?'Theory':'Practical',component.credit,req.auth.userId])).rows[0].subject_master_id;
        }
        for(const component of data.components)await client.query('INSERT INTO subject_components(subject_master_id,subject_type,credit) VALUES($1,$2,$3)',[id,component.type,component.credit]);
        const component=(await client.query("SELECT subject_type,credit FROM subject_components WHERE subject_master_id=$1 ORDER BY CASE subject_type WHEN 'THEORY' THEN 0 ELSE 1 END LIMIT 1",[id])).rows[0];
        await client.query('UPDATE subject_masters SET subject_type=$1,credit=$2,updated_at=NOW(),updated_by=$3 WHERE subject_master_id=$4',[component.subject_type==='THEORY'?'Theory':'Practical',component.credit,req.auth.userId,id]);
      }
      await client.query('COMMIT');res.status(201).json({ok:true,message:`${rows.length} subjects imported successfully.`});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code?500:400).json({ok:false,message:error.code?'Unable to import subjects. No subjects were saved.':`${error.message} No subjects were saved.`});}finally{client?.release();}
  });
  const save = async (req,res) => {
    let data;
    try { data=validateSubject(req.body || {}); } catch(error) { return res.status(400).json({ok:false,message:error.message}); }
    const id = req.params.id ? Number(req.params.id) : null;
    if (req.params.id && (!Number.isSafeInteger(id) || id<=0)) return res.status(400).json({ok:false,message:'Invalid subject.'});
    let client;
    try {
      client=await pool.connect(); await client.query('BEGIN');
      const programme=(await client.query(`SELECT p.department_id FROM programmes p JOIN semesters s ON s.programme_id=p.programme_id
        WHERE p.programme_id=$1 AND s.semester_id=$2 AND p.is_active=TRUE AND s.is_active=TRUE`,[data.programmeId,data.semesterId])).rows[0];
      if (!programme) { await client.query('ROLLBACK'); return res.status(400).json({ok:false,message:'Select an active semester belonging to the selected programme.'}); }
      let existing;
      if (!id) {
        // Serialize separate Theory/Practical saves for the same programme, semester and code.
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`${data.programmeId}:${data.semesterId}:${data.code}`]);
        existing=(await client.query(`SELECT subject_master_id,subject_name,is_active FROM subject_masters
          WHERE programme_id=$1 AND semester_id=$2 AND UPPER(subject_code)=$3 FOR UPDATE`,[data.programmeId,data.semesterId,data.code])).rows[0];
        if(existing){
          const previous=(await client.query('SELECT subject_type AS type,credit FROM subject_components WHERE subject_master_id=$1',[existing.subject_master_id])).rows;
          const missing=data.components.filter(component=>!previous.some(c=>c.type===component.type));
          if(!missing.length){
            await client.query('ROLLBACK');return res.status(409).json({ok:false,message:'This subject type already exists for this code, Programme and Semester. Use Edit to change its credit.'});
          }
          if(existing.subject_name.toLowerCase()!==data.name.toLowerCase()||existing.is_active!==data.isActive){
            await client.query('ROLLBACK');return res.status(409).json({ok:false,message:'Use the existing subject name and status when adding its missing type, or use Edit to update the subject.'});
          }
          data.components=[...previous,...missing];
          data.name=existing.subject_name;
        }
      }
      const first=data.components.find(c=>c.type==='THEORY') || data.components[0];
      const values=[data.programmeId,data.semesterId,data.code,data.name,data.isActive,programme.department_id,first.type==='THEORY'?'Theory':'Practical',first.credit,req.auth.userId];
      const updateId=id||existing?.subject_master_id;
      const result = updateId ? await client.query(`UPDATE subject_masters SET programme_id=$1,semester_id=$2,subject_code=$3,subject_name=$4,is_active=$5,
        department_id=$6,subject_type=$7,credit=$8,updated_by=$9,updated_at=NOW() WHERE subject_master_id=$10 AND programme_id IS NOT NULL RETURNING subject_master_id`,[...values,updateId])
        : await client.query(`INSERT INTO subject_masters(programme_id,semester_id,subject_code,subject_name,is_active,department_id,subject_type,credit,created_by,subject_category)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'Professional Core') RETURNING subject_master_id`,values);
      if (!result.rowCount) { await client.query('ROLLBACK'); return res.status(404).json({ok:false,message:'Subject not found.'}); }
      const subjectId=result.rows[0].subject_master_id;
      for (const component of data.components) await client.query(`INSERT INTO subject_components(subject_master_id,subject_type,credit) VALUES($1,$2,$3)
        ON CONFLICT(subject_master_id,subject_type) DO UPDATE SET credit=EXCLUDED.credit,updated_at=NOW()`,[subjectId,component.type,component.credit]);
      await client.query('DELETE FROM subject_components WHERE subject_master_id=$1 AND NOT(subject_type=ANY($2::text[]))',[subjectId,data.components.map(c=>c.type)]);
      await client.query('COMMIT'); res.status(id?200:201).json({ok:true,id:subjectId,message:id?'Subject updated successfully.':existing?'Subject component added successfully.':'Subject saved successfully.'});
    } catch(error) {
      if(client)await client.query('ROLLBACK'); console.error('Save academic subject:',error.message);
      res.status(error.code==='23505'?409:error.code==='23503'?409:500).json({ok:false,message:error.code==='23505'?'Subject Code already exists in this Programme and Semester.':error.code==='23503'?'A selected component is used by another module and cannot be removed.':'Unable to save subject.'});
    } finally {client?.release();}
  };
  app.post('/api/academic-subjects',authenticate,admin,save);
  app.put('/api/academic-subjects/:id',authenticate,admin,save);
  app.delete('/api/academic-subjects/:id',authenticate,admin,async(req,res)=>{
    const id=Number(req.params.id);
    if(!Number.isSafeInteger(id)||id<=0)return res.status(400).json({ok:false,message:'Invalid subject.'});
    try {
      // PostgreSQL checks all referencing foreign keys atomically; component rows cascade only after a successful delete.
      const result=await pool.query('DELETE FROM subject_masters WHERE subject_master_id=$1 AND programme_id IS NOT NULL RETURNING subject_master_id',[id]);
      if(!result.rowCount)return res.status(404).json({ok:false,message:'Subject not found.'});
      res.json({ok:true,message:'Subject deleted successfully.'});
    } catch(error){res.status(error.code==='23503'?409:500).json({ok:false,message:error.code==='23503'?'This subject is used in another module and cannot be deleted.':'Unable to delete subject.'});}
  });
}
