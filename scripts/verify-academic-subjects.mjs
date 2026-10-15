// Local integration check: creates uniquely named subjects and removes them afterward.
import 'dotenv/config';
import assert from 'node:assert/strict';
import express from 'express';
import pg from 'pg';
import {registerAcademicSubjectRoutes,validateSubject} from '../server/academic-subjects.js';

const pool=new pg.Pool({host:process.env.DB_HOST,port:Number(process.env.DB_PORT),database:process.env.DB_NAME,user:process.env.DB_USER,password:process.env.DB_PASSWORD,max:1,connectionTimeoutMillis:5000});
const code=`VERIFY_${Date.now()}`;
const referenceTable=`public.verify_subject_reference_${Date.now()}`;
const app=express();app.use(express.json());
registerAcademicSubjectRoutes(app,pool,(req,_res,next)=>{req.auth={role:req.get('x-test-role')||'ADMIN',userId:null};next();});
const server=app.listen(0,'127.0.0.1');
await new Promise(resolve=>server.once('listening',resolve));
const base=`http://127.0.0.1:${server.address().port}/api/academic-subjects`;
async function call(path='',method='GET',data,role='ADMIN'){
  const response=await fetch(base+path,{method,headers:{'Content-Type':'application/json','x-test-role':role},body:data?JSON.stringify(data):undefined});
  return {status:response.status,body:await response.json()};
}
try{
  const {body}=await call();assert.equal(body.ok,true);
  const semester=body.semesters.find(s=>s.is_active&&body.programmes.some(p=>p.is_active&&p.id===s.programme_id));
  assert.ok(semester,'Create an active Programme and Semester before running verification.');
  const data={programmeId:semester.programme_id,semesterId:semester.id,code,name:'Subject integration verification',isActive:true,components:[{type:'THEORY',credit:3},{type:'PRACTICAL',credit:1}]};
  assert.throws(()=>validateSubject({...data,components:[]}));
  assert.throws(()=>validateSubject({...data,components:[{type:'THEORY',credit:-1}]}));
  assert.throws(()=>validateSubject({...data,components:[{type:'THEORY',credit:''}]}));
  assert.throws(()=>validateSubject({...data,components:[{type:'THEORY',credit:1.234}]}));
  assert.equal((await call('','POST',data,'EMPLOYEE')).status,403);
  assert.equal((await call('','POST',{...data,components:[]})).status,400);
  const separate={...data,code:code+'_SEP',components:[{type:'THEORY',credit:3}]};
  const theory=await call('','POST',separate);assert.equal(theory.status,201);
  const practical=await call('','POST',{...separate,components:[{type:'THEORY',credit:9},{type:'PRACTICAL',credit:1}]});assert.equal(practical.status,201);assert.equal(practical.body.id,theory.body.id);
  const merged=(await call()).body.subjects.find(s=>s.id===theory.body.id);assert.equal(merged.components.length,2);
  assert.deepEqual(merged.components.map(c=>[c.type,Number(c.credit)]),[['THEORY',3],['PRACTICAL',1]]);
  assert.equal((await call('','POST',{...separate,components:[{type:'PRACTICAL',credit:2}]})).status,409);
  const displayed=(await pool.query('SELECT subject_code,subject_type,credit FROM subject_component_list WHERE subject_master_id=$1 ORDER BY subject_type DESC',[theory.body.id])).rows;assert.equal(displayed.length,2);assert.ok(displayed.every(row=>row.subject_code===separate.code));
  const upload={programmeId:semester.programme_id,semesterId:semester.id,rows:[{...data,code:code+'_BULK1',components:[{type:'THEORY',credit:3}]},{...data,code:code+'_BULK2',components:[{type:'THEORY',credit:3}]},{...data,code:code+'_BULK2',components:[{type:'PRACTICAL',credit:1}]}]};
  assert.equal((await call('/bulk','POST',upload,'EMPLOYEE')).status,403);
  assert.equal((await call('/bulk','POST',{...upload,rows:[{...data,programmeId:''}]})).status,400);
  assert.equal((await call('/bulk','POST',{...upload,rows:[{...data,semesterId:''}]})).status,400);
  const repeated={rows:[{...data,code:code+'_BULK2',components:[{type:'THEORY',credit:3}]},{...data,code:code+'_BULK2',components:[{type:'THEORY',credit:1}]}]};
  assert.equal((await call('/bulk','POST',repeated)).status,400);
  assert.equal((await call('/bulk','POST',upload)).status,201);
  const bulkSubject=(await call()).body.subjects.find(s=>s.code===code+'_BULK2');assert.equal(bulkSubject.components.length,2);
  const alternateSemester=body.semesters.find(s=>s.is_active&&s.programme_id===semester.programme_id&&s.id!==semester.id);
  if(alternateSemester){
    const mixed={rows:[{...data,code:code+'_MIXED'},{...data,code:code+'_MIXED',semesterId:alternateSemester.id}]};
    assert.equal((await call('/bulk','POST',mixed)).status,201);
    assert.equal((await call()).body.subjects.filter(s=>s.code===code+'_MIXED').length,2);
  }
  const rollback={...upload,rows:[{...data,code:code+'_ROLLBACK'},{...data,code:code+'_BULK1',components:[{type:'THEORY',credit:3}]}]};
  assert.equal((await call('/bulk','POST',rollback)).status,400);
  assert.equal((await call()).body.subjects.some(s=>s.code===code+'_ROLLBACK'),false);
  const created=await call('','POST',data);assert.equal(created.status,201);const id=created.body.id;
  assert.equal((await call('','POST',data)).status,409);
  let subject=(await call()).body.subjects.find(s=>s.id===id);assert.equal(subject.components.length,2);
  assert.deepEqual(subject.components.map(c=>[c.type,Number(c.credit)]),[['THEORY',3],['PRACTICAL',1]]);
  assert.equal((await call(`/${id}`,'PUT',{...data,isActive:false,components:[{type:'PRACTICAL',credit:2}]})).status,200);
  subject=(await call()).body.subjects.find(s=>s.id===id);assert.equal(subject.is_active,false);assert.equal(subject.components.length,1);assert.equal(subject.components[0].type,'PRACTICAL');
  assert.equal((await call(`/${id}`,'PUT',{...data,components:[{type:'THEORY',credit:3}]})).status,200);
  const other=body.semesters.find(s=>s.is_active&&s.programme_id===semester.programme_id&&s.id!==semester.id);
  if(other)assert.equal((await call('','POST',{...data,semesterId:other.id})).status,201);
  const mismatch=body.semesters.find(s=>s.programme_id!==semester.programme_id);
  if(mismatch)assert.equal((await call('','POST',{...data,semesterId:mismatch.id})).status,400);
  await pool.query(`CREATE TABLE ${referenceTable}(subject_id BIGINT REFERENCES public.subject_masters(subject_master_id))`);
  await pool.query(`INSERT INTO ${referenceTable} VALUES($1)`,[id]);
  assert.equal((await call(`/${id}`,'DELETE')).status,409);
  assert.equal((await call()).body.subjects.find(s=>s.id===id).components.length,1);
  await pool.query(`DROP TABLE ${referenceTable}`);
  assert.equal((await call(`/${id}`,'DELETE')).status,200);
  assert.equal(Number((await pool.query('SELECT COUNT(*) FROM subject_components WHERE subject_master_id=$1',[id])).rows[0].count),0);
  console.log('Passed: separate credits, combined edit, Theory/Practical-only saves, scoped uniqueness, validation, administrator access, dependency protection and deletion.');
}finally{
  await pool.query(`DROP TABLE IF EXISTS ${referenceTable}`);
  await pool.query('DELETE FROM subject_masters WHERE subject_code=ANY($1::text[])',[[code,code+'_SEP',code+'_BULK1',code+'_BULK2',code+'_ROLLBACK',code+'_MIXED']]);
  await new Promise(resolve=>server.close(resolve));await pool.end();
}
