import {createHash} from 'node:crypto';
export function sectionMasterCode(name){
  const cleaned=name.toUpperCase().replace(/^SECTION\s+/,'').replace(/[^A-Z0-9]+/g,'-').replace(/^-|-$/g,'')||'SECTION';
  const code='SEC-'+cleaned;
  return code.length<=30?code:'SEC-'+cleaned.slice(0,18)+'-'+createHash('sha256').update(name.toLowerCase()).digest('hex').slice(0,6);
}
export function registerSectionMasterRoutes(app,pool,authenticate){
  const admin=(req,res,next)=>['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role)?next():res.status(403).json({ok:false,message:'Only administrators can change section masters.'});
  app.get('/api/section-masters',authenticate,async(_req,res)=>{
    try{const result=await pool.query('SELECT section_master_id AS id,section_master_code AS code,section_master_name AS name,is_active FROM section_masters ORDER BY section_master_name');res.json({ok:true,sections:result.rows});}catch{res.status(500).json({ok:false,message:'Unable to load section masters.'});}
  });
  const save=async(req,res)=>{
    const name=String(req.body.name||'').trim(),id=req.params.id?Number(req.params.id):null;
    if(!name||name.length>100||(req.params.id&&(!Number.isSafeInteger(id)||id<=0))||(req.body.isActive!==undefined&&typeof req.body.isActive!=='boolean'))return res.status(400).json({ok:false,message:'Enter a Section Master Name of up to 100 characters and a valid Status.'});
    try{
      const active=req.body.isActive??true;
      const result=id?await pool.query('UPDATE section_masters SET section_master_name=$1,is_active=$2,updated_at=NOW(),updated_by=$3 WHERE section_master_id=$4 RETURNING section_master_id,section_master_code',[name,active,req.auth.userId,id]):await pool.query('INSERT INTO section_masters(section_master_code,section_master_name,is_active,created_by) VALUES($1,$2,$3,$4) RETURNING section_master_id,section_master_code',[sectionMasterCode(name),name,active,req.auth.userId]);
      if(!result.rowCount)return res.status(404).json({ok:false,message:'Section Master not found.'});res.status(id?200:201).json({ok:true,id:result.rows[0].section_master_id,code:result.rows[0].section_master_code,message:id?'Section Master updated successfully.':'Section Master created successfully.'});
    }catch(error){res.status(error.code==='23505'?409:500).json({ok:false,message:error.code==='23505'?'Section Master Name already exists.':'Unable to save Section Master.'});}
  };
  app.post('/api/section-masters',authenticate,admin,save);app.put('/api/section-masters/:id',authenticate,admin,save);
  app.delete('/api/section-masters/:id',authenticate,admin,async(req,res)=>{
    const id=Number(req.params.id);if(!Number.isSafeInteger(id)||id<=0)return res.status(400).json({ok:false,message:'Invalid Section Master.'});
    try{const result=await pool.query('DELETE FROM section_masters WHERE section_master_id=$1 RETURNING section_master_id',[id]);if(!result.rowCount)return res.status(404).json({ok:false,message:'Section Master not found.'});res.json({ok:true,message:'Section Master deleted successfully.'});}catch(error){res.status(error.code==='23503'?409:500).json({ok:false,message:error.code==='23503'?'This Section Master is in use and cannot be deleted.':'Unable to delete Section Master.'});}
  });
}
