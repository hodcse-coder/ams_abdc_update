import {validateStudentImportRows,resolveStudentImportMasters} from '../shared/student-import.js';
export function registerStudentImportRoute(app,pool,authenticate,insertStudent){
  app.post('/api/students/import',authenticate,async(req,res)=>{
    if(!['ADMIN','SUPER_ADMIN','INSTITUTE_ADMIN'].includes(req.auth.role))return res.status(403).json({ok:false,message:'Only administrators can import students.'});
    let rows;try{rows=validateStudentImportRows(req.body.rows);}catch(error){return res.status(400).json({ok:false,message:error.message});}let client;
    try{
      client=await pool.connect();await client.query('BEGIN');
      const programmes=(await client.query('SELECT programme_id AS id,department_id,programme_code AS code,programme_name AS name FROM programmes WHERE is_active')).rows;
      const years=(await client.query('SELECT academic_year_id AS id,year_label AS code,academic_year_name AS name,start_date::text,end_date::text FROM academic_years WHERE is_active')).rows;
      rows=resolveStudentImportMasters(rows,{programmes,academicYears:years});
      for(let index=0;index<rows.length;index++){
        const row=rows[index];
        if((await client.query('SELECT 1 FROM students WHERE UPPER(admission_number)=UPPER($1) OR UPPER(admission_no)=UPPER($1)',[row.admissionNumber])).rowCount)throw new Error(`Row ${index+2}: Admission No already exists.`);
        await insertStudent(client,{...row,semesterId:null},req.auth.userId);
      }
      await client.query('COMMIT');res.status(201).json({ok:true,message:`${rows.length} students imported successfully.`});
    }catch(error){if(client)await client.query('ROLLBACK');res.status(error.code==='23505'?409:400).json({ok:false,message:error.code==='23505'?'A student number already exists. No students were imported.':`${error.message} No students were imported.`});}finally{client?.release();}
  });
}
