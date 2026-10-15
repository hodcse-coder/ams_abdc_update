const fields={firstName:'first_name',middleName:'middle_name',lastName:'last_name',gender:'gender',dateOfBirth:'date_of_birth',joiningDate:'date_of_joining',bloodGroup:'blood_group',maritalStatus:'marital_status',mobile:'mobile',officialEmail:'official_email',personalEmail:'personal_email',address:'address',permanentAddress:'permanent_address',category:'employee_category',status:'status',photoUrl:'photo_url',employeeType:'employment_type',healthNotes:'health_notes'};
const extraFields=['teacherRegistration','title','nameAlias','birthPlace','experience','caste','nationality','religion','thumb','lunch','transport','fatherName','motherName','emergencyContact','documents'];
export async function updateEmployeeRecord(pool,id,data){
  if(!Number.isSafeInteger(id)||id<=0||typeof data.firstName!=='string'||!data.firstName.trim())throw new Error('First Name is required.');
  if(data.employeeType!==undefined&&(!String(data.employeeType).trim()||!['TEACHING','NON-TEACHING','NON_TEACHING'].includes(String(data.employeeType).toUpperCase())))throw new Error('Select a valid Employee Type.');
  if(data.status!==undefined&&!['ACTIVE','INACTIVE','ON_LEAVE'].includes(String(data.status).toUpperCase()))throw new Error('Select a valid Employment Status.');
  for(const key of ['dateOfBirth','joiningDate'])if(data[key]&&(!/^\d{4}-\d{2}-\d{2}$/.test(data[key])||Number.isNaN(Date.parse(data[key]))||new Date(data[key]).toISOString().slice(0,10)!==data[key]))throw new Error('Enter valid dates in Date of Birth and Joining Date.');
  const client=await pool.connect();
  try{
    await client.query('BEGIN');
    const existing=(await client.query('SELECT employee_id FROM employees WHERE employee_id=$1 FOR UPDATE',[id])).rows[0];
    if(!existing){await client.query('ROLLBACK');return null;}
    const assignments=[],values=[];
    const add=(column,value)=>{values.push(value);assignments.push(column+'=$'+values.length);};
    for(const [key,column] of Object.entries(fields))if(Object.hasOwn(data,key)){
      // Health notes are stored with extended details so existing schemas stay compatible.
      if(key==='healthNotes')continue;
      if(data[key]!==null&&typeof data[key]!=='string')throw new Error('Enter valid text for '+key+'.');
      let value=data[key]?.trim()||null;if(key==='status'&&value)value=value.toUpperCase();
      add(column,value);
    }
    for(const item of [
      {key:'department',table:'departments',id:'department_id',name:'department_name',code:'department_code'},
      {key:'designation',table:'designations',id:'designation_id',name:'designation_name',code:'designation_code'},
      {key:'campus',table:'campuses',id:'campus_id',name:'campus_name',code:'campus_code'}
    ])if(Object.hasOwn(data,item.key)){
      const value=String(data[item.key]||'').trim();if(!value){add(item.id,null);continue;}
      const matches=await client.query(`SELECT ${item.id} AS id FROM ${item.table} WHERE LOWER(${item.name})=LOWER($1) OR LOWER(${item.code})=LOWER($1)`,[value]);
      if(matches.rowCount!==1)throw new Error('Select a valid '+item.key+'.');add(item.id,matches.rows[0].id);
    }
    const extras={};for(const key of [...extraFields,'healthNotes'])if(Object.hasOwn(data,key))extras[key]=String(data[key]??'').trim();
    values.push(JSON.stringify(extras));assignments.push(`profile_details=COALESCE(profile_details,'{}'::jsonb)||$${values.length}::jsonb`);
    values.push(id);const result=await client.query('UPDATE employees SET '+assignments.join(',')+' WHERE employee_id=$'+values.length+' RETURNING employee_id',values);
    await client.query('COMMIT');return result.rows[0];
  }catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}
}
export function registerEmployeeUpdateRoute(app,pool,authenticate){
  app.put('/api/employees/:id',authenticate,async(req,res)=>{
    if(!['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role))return res.status(403).json({ok:false,message:'Only administrators can edit employees.'});
    try{const result=await updateEmployeeRecord(pool,Number(req.params.id),req.body||{});if(!result)return res.status(404).json({ok:false,message:'Employee not found.'});res.json({ok:true,message:'Employee updated successfully.'});}catch(error){res.status(error.code==='23505'?409:400).json({ok:false,message:error.code==='23505'?'An employee with these unique details already exists.':error.message});}
  });
}
