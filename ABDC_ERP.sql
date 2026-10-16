-- ABDC ERP master database structure
-- Generated 2026-10-15. PostgreSQL 17.
-- Connection details (database credentials, not application login credentials):
-- host: "localhost"
-- port: "5432"
-- database: "postgres"
-- username: "postgres"
-- password: "replace_with_your_database_password"
-- Import into an EMPTY database using psql -v ON_ERROR_STOP=1 -d DATABASE -f ABDC_ERP.sql.
-- Connect with the username/password above; this file does not change database roles or passwords.
-- Includes current tables, sequences, views, functions, constraints and indexes.
-- Structure only: existing student/user records and application password hashes are not exported.
-- Additional legacy tables use current batch, section, subject and period master foreign keys.
-- Original source scripts are preserved verbatim in inactive archive blocks below.
-- Server startup reads only its named migration blocks, never the full structure dump.

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.10
-- Dumped by pg_dump version 17.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ABDC_DB; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA "ABDC_DB";


--
-- Name: academics; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA academics;


--
-- Name: communication; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA communication;


--
-- Name: mentoring; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA mentoring;


--
-- Name: permission_management; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA permission_management;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: validate_academic_break(); Type: FUNCTION; Schema: academics; Owner: -
--

CREATE FUNCTION academics.validate_academic_break() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start TIME;
    v_end TIME;
BEGIN
    SELECT college_start_time, college_end_time
      INTO v_start, v_end
      FROM academics.academic_time_configurations
     WHERE time_configuration_id = NEW.time_configuration_id;

    IF NEW.start_time < v_start OR NEW.end_time > v_end THEN
        RAISE EXCEPTION 'Break time must be within college start and end time.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM academics.academic_breaks ab
         WHERE ab.time_configuration_id = NEW.time_configuration_id
           AND ab.academic_break_id <> COALESCE(NEW.academic_break_id,0)
           AND ab.is_active = TRUE
           AND NEW.start_time < ab.end_time
           AND NEW.end_time > ab.start_time
    ) THEN
        RAISE EXCEPTION 'Break time overlaps another active break.';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: validate_timetable_entry(); Type: FUNCTION; Schema: academics; Owner: -
--

CREATE FUNCTION academics.validate_timetable_entry() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_is_teaching BOOLEAN;
BEGIN
    SELECT is_teaching_period INTO v_is_teaching
      FROM academics.academic_periods
     WHERE period_id = NEW.period_id;

    IF COALESCE(v_is_teaching,FALSE) = FALSE THEN
        RAISE EXCEPTION 'A subject cannot be assigned to a break or lunch period.';
    END IF;

    IF NEW.faculty_employee_id IS NOT NULL AND EXISTS (
        SELECT 1
          FROM academics.timetable_entries te
          JOIN academics.timetable_headers th ON th.timetable_id = te.timetable_id
         WHERE te.faculty_employee_id = NEW.faculty_employee_id
           AND te.week_day_id = NEW.week_day_id
           AND te.period_id = NEW.period_id
           AND te.timetable_entry_id <> COALESCE(NEW.timetable_entry_id,0)
           AND th.timetable_status IN ('Draft','Under Review','Published')
    ) THEN
        RAISE EXCEPTION 'Faculty is already assigned during this day and period.';
    END IF;

    IF NEW.classroom_id IS NOT NULL AND EXISTS (
        SELECT 1
          FROM academics.timetable_entries te
          JOIN academics.timetable_headers th ON th.timetable_id = te.timetable_id
         WHERE te.classroom_id = NEW.classroom_id
           AND te.week_day_id = NEW.week_day_id
           AND te.period_id = NEW.period_id
           AND te.timetable_entry_id <> COALESCE(NEW.timetable_entry_id,0)
           AND th.timetable_status IN ('Draft','Under Review','Published')
    ) THEN
        RAISE EXCEPTION 'Room is already occupied during this day and period.';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: validate_mentor_reviewer_detail(); Type: FUNCTION; Schema: mentoring; Owner: -
--

CREATE FUNCTION mentoring.validate_mentor_reviewer_detail() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    mentor_employee_id BIGINT;
BEGIN
    SELECT mentor_id INTO mentor_employee_id
    FROM mentoring.mentor_reviewer_allotments
    WHERE mentor_reviewer_allotment_id=NEW.mentor_reviewer_allotment_id;
    IF mentor_employee_id=NEW.reviewer_id THEN
        RAISE EXCEPTION 'Mentor cannot also be selected as a reviewer.';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: validate_user_type_link(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_user_type_link() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE type_code VARCHAR(30);
BEGIN
  SELECT user_type_code INTO type_code FROM user_types WHERE user_type_id=NEW.user_type_id;
  IF type_code='EMPLOYEE' AND (NEW.employee_id IS NULL OR NEW.student_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Employee must be selected for Employee user type.';
  ELSIF type_code='STUDENT' AND (NEW.student_id IS NULL OR NEW.employee_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Student must be selected for Student user type.';
  ELSIF type_code='ADMIN' AND NEW.student_id IS NOT NULL THEN
    RAISE EXCEPTION 'Admin user cannot be linked to a student.';
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: user_logins; Type: TABLE; Schema: ABDC_DB; Owner: -
--

CREATE TABLE "ABDC_DB".user_logins (
    user_id bigint NOT NULL,
    login_id character varying(100) NOT NULL,
    password_hash text NOT NULL,
    user_type character varying(20) NOT NULL,
    employee_id bigint,
    student_id bigint,
    display_name character varying(150),
    photo_path text,
    account_status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    force_password_change boolean DEFAULT true NOT NULL,
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    last_login_at timestamp without time zone,
    created_by bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone,
    CONSTRAINT chk_login_person CHECK ((NOT ((employee_id IS NOT NULL) AND (student_id IS NOT NULL)))),
    CONSTRAINT user_logins_account_status_check CHECK (((account_status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'INACTIVE'::character varying, 'LOCKED'::character varying])::text[]))),
    CONSTRAINT user_logins_user_type_check CHECK (((user_type)::text = ANY ((ARRAY['SUPER_ADMIN'::character varying, 'ADMIN'::character varying, 'SUB_ADMIN'::character varying, 'USER'::character varying])::text[])))
);


--
-- Name: user_logins_user_id_seq; Type: SEQUENCE; Schema: ABDC_DB; Owner: -
--

CREATE SEQUENCE "ABDC_DB".user_logins_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_logins_user_id_seq; Type: SEQUENCE OWNED BY; Schema: ABDC_DB; Owner: -
--

ALTER SEQUENCE "ABDC_DB".user_logins_user_id_seq OWNED BY "ABDC_DB".user_logins.user_id;


--
-- Name: academic_breaks; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.academic_breaks (
    academic_break_id bigint NOT NULL,
    time_configuration_id bigint NOT NULL,
    break_name character varying(100) NOT NULL,
    break_type character varying(20) NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    display_order integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT academic_breaks_break_type_check CHECK (((break_type)::text = ANY (ARRAY[('Tea Break'::character varying)::text, ('Lunch'::character varying)::text, ('Activity'::character varying)::text, ('Other'::character varying)::text]))),
    CONSTRAINT academic_breaks_check CHECK ((end_time > start_time)),
    CONSTRAINT academic_breaks_display_order_check CHECK ((display_order > 0))
);


--
-- Name: academic_breaks_academic_break_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.academic_breaks_academic_break_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: academic_breaks_academic_break_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.academic_breaks_academic_break_id_seq OWNED BY academics.academic_breaks.academic_break_id;


--
-- Name: academic_periods; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.academic_periods (
    period_id bigint NOT NULL,
    time_configuration_id bigint NOT NULL,
    period_code character varying(20) NOT NULL,
    period_name character varying(80) NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    duration_minutes integer NOT NULL,
    period_type character varying(20) NOT NULL,
    display_order integer NOT NULL,
    is_teaching_period boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT academic_periods_check CHECK ((end_time > start_time)),
    CONSTRAINT academic_periods_display_order_check CHECK ((display_order > 0)),
    CONSTRAINT academic_periods_duration_minutes_check CHECK ((duration_minutes > 0)),
    CONSTRAINT academic_periods_period_type_check CHECK (((period_type)::text = ANY (ARRAY[('Teaching'::character varying)::text, ('Break'::character varying)::text, ('Lunch'::character varying)::text, ('Activity'::character varying)::text, ('Other'::character varying)::text])))
);


--
-- Name: academic_periods_period_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.academic_periods_period_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: academic_periods_period_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.academic_periods_period_id_seq OWNED BY academics.academic_periods.period_id;


--
-- Name: academic_time_configuration_days; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.academic_time_configuration_days (
    time_configuration_id bigint NOT NULL,
    week_day_id smallint NOT NULL
);


--
-- Name: academic_time_configurations; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.academic_time_configurations (
    time_configuration_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    configuration_name character varying(150) NOT NULL,
    college_start_time time without time zone NOT NULL,
    college_end_time time without time zone NOT NULL,
    teaching_period_minutes integer DEFAULT 55 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT academic_time_configurations_check CHECK ((college_end_time > college_start_time)),
    CONSTRAINT academic_time_configurations_teaching_period_minutes_check CHECK ((teaching_period_minutes > 0))
);


--
-- Name: academic_time_configurations_time_configuration_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.academic_time_configurations_time_configuration_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: academic_time_configurations_time_configuration_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.academic_time_configurations_time_configuration_id_seq OWNED BY academics.academic_time_configurations.time_configuration_id;


--
-- Name: attendance_calendar_dates; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.attendance_calendar_dates (
    attendance_calendar_date_id bigint NOT NULL,
    attendance_calendar_setting_id bigint NOT NULL,
    attendance_date date NOT NULL,
    is_permitted boolean DEFAULT true NOT NULL,
    open_time time without time zone,
    close_time time without time zone,
    remarks text
);


--
-- Name: attendance_calendar_dates_attendance_calendar_date_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.attendance_calendar_dates_attendance_calendar_date_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attendance_calendar_dates_attendance_calendar_date_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.attendance_calendar_dates_attendance_calendar_date_id_seq OWNED BY academics.attendance_calendar_dates.attendance_calendar_date_id;


--
-- Name: attendance_calendar_settings; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.attendance_calendar_settings (
    attendance_calendar_setting_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    programme_id bigint,
    programme_batch_id bigint,
    semester_id bigint,
    programme_section_id bigint,
    permission_type character varying(20) NOT NULL,
    start_date date,
    end_date date,
    allow_attendance boolean DEFAULT true NOT NULL,
    attendance_open_time time without time zone,
    attendance_close_time time without time zone,
    is_active boolean DEFAULT true NOT NULL,
    remarks text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT attendance_calendar_settings_permission_type_check CHECK (((permission_type)::text = ANY ((ARRAY['Single Day'::character varying, 'Date Range'::character varying, 'Selected Dates'::character varying, 'Weekly Pattern'::character varying, 'All Working Days'::character varying])::text[])))
);


--
-- Name: attendance_calendar_settings_attendance_calendar_setting_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.attendance_calendar_settings_attendance_calendar_setting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attendance_calendar_settings_attendance_calendar_setting_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.attendance_calendar_settings_attendance_calendar_setting_id_seq OWNED BY academics.attendance_calendar_settings.attendance_calendar_setting_id;


--
-- Name: attendance_calendar_weekdays; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.attendance_calendar_weekdays (
    attendance_calendar_weekday_id bigint NOT NULL,
    attendance_calendar_setting_id bigint NOT NULL,
    day_of_week smallint NOT NULL,
    is_permitted boolean DEFAULT true NOT NULL,
    CONSTRAINT attendance_calendar_weekdays_day_of_week_check CHECK (((day_of_week >= 1) AND (day_of_week <= 7)))
);


--
-- Name: attendance_calendar_weekdays_attendance_calendar_weekday_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.attendance_calendar_weekdays_attendance_calendar_weekday_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attendance_calendar_weekdays_attendance_calendar_weekday_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.attendance_calendar_weekdays_attendance_calendar_weekday_id_seq OWNED BY academics.attendance_calendar_weekdays.attendance_calendar_weekday_id;


--
-- Name: course_outcome_codes; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.course_outcome_codes (
    co_code_id bigint NOT NULL,
    co_code character varying(20) NOT NULL,
    co_number integer NOT NULL,
    display_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT course_outcome_codes_co_number_check CHECK ((co_number > 0)),
    CONSTRAINT course_outcome_codes_display_order_check CHECK ((display_order > 0))
);


--
-- Name: course_outcome_codes_co_code_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.course_outcome_codes_co_code_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: course_outcome_codes_co_code_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.course_outcome_codes_co_code_id_seq OWNED BY academics.course_outcome_codes.co_code_id;


--
-- Name: course_outcomes; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.course_outcomes (
    course_outcome_id bigint NOT NULL,
    subject_master_id bigint NOT NULL,
    co_code_id bigint NOT NULL,
    co_description text NOT NULL,
    faculty_employee_id bigint,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone
);


--
-- Name: course_outcomes_course_outcome_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.course_outcomes_course_outcome_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: course_outcomes_course_outcome_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.course_outcomes_course_outcome_id_seq OWNED BY academics.course_outcomes.course_outcome_id;


--
-- Name: faculty_subject_assignments; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.faculty_subject_assignments (
    faculty_subject_assignment_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    programme_batch_id bigint,
    semester_id bigint,
    programme_section_id bigint,
    subject_id bigint NOT NULL,
    faculty_employee_id bigint NOT NULL,
    assignment_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    assigned_by bigint,
    CONSTRAINT faculty_subject_assignments_assignment_status_check CHECK (((assignment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Completed'::character varying)::text])))
);


--
-- Name: faculty_subject_assignments_faculty_subject_assignment_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.faculty_subject_assignments_faculty_subject_assignment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: faculty_subject_assignments_faculty_subject_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.faculty_subject_assignments_faculty_subject_assignment_id_seq OWNED BY academics.faculty_subject_assignments.faculty_subject_assignment_id;


--
-- Name: lecture_notes; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.lecture_notes (
    lecture_note_id bigint NOT NULL,
    subject_master_id bigint NOT NULL,
    unit_name character varying(80) NOT NULL,
    note_title character varying(250) NOT NULL,
    file_name character varying(255),
    file_mime_type character varying(120),
    file_size bigint,
    file_data bytea,
    note_url text,
    description text,
    publish_status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    material_type character varying(20) DEFAULT 'LECTURE_NOTE'::character varying NOT NULL,
    duration_minutes integer,
    CONSTRAINT lecture_notes_check CHECK (((file_data IS NOT NULL) OR (note_url IS NOT NULL))),
    CONSTRAINT lecture_notes_duration_check CHECK (((duration_minutes IS NULL) OR (duration_minutes > 0))),
    CONSTRAINT lecture_notes_material_type_check CHECK (((material_type)::text = ANY (ARRAY[('LECTURE_NOTE'::character varying)::text, ('VIDEO_LECTURE'::character varying)::text, ('PPT'::character varying)::text]))),
    CONSTRAINT lecture_notes_publish_status_check CHECK (((publish_status)::text = ANY ((ARRAY['Draft'::character varying, 'Published'::character varying, 'Submitted'::character varying])::text[])))
);


--
-- Name: lecture_notes_lecture_note_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.lecture_notes_lecture_note_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lecture_notes_lecture_note_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.lecture_notes_lecture_note_id_seq OWNED BY academics.lecture_notes.lecture_note_id;


--
-- Name: lesson_plan_books; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.lesson_plan_books (
    lesson_plan_book_id bigint NOT NULL,
    lesson_plan_id bigint NOT NULL,
    preferred_book_id bigint,
    book_title character varying(255) NOT NULL,
    author_name character varying(255),
    publisher_name character varying(255),
    edition character varying(80),
    isbn character varying(30),
    book_sequence integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint
);


--
-- Name: lesson_plan_books_lesson_plan_book_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.lesson_plan_books_lesson_plan_book_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lesson_plan_books_lesson_plan_book_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.lesson_plan_books_lesson_plan_book_id_seq OWNED BY academics.lesson_plan_books.lesson_plan_book_id;


--
-- Name: lesson_plan_headers; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.lesson_plan_headers (
    lesson_plan_id bigint NOT NULL,
    faculty_subject_assignment_id bigint NOT NULL,
    lesson_plan_title character varying(200),
    plan_status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    total_planned_topics integer DEFAULT 0 NOT NULL,
    total_planned_periods integer DEFAULT 0 NOT NULL,
    submitted_at timestamp with time zone,
    approved_at timestamp with time zone,
    approved_by bigint,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT lesson_plan_headers_plan_status_check CHECK (((plan_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Approved'::character varying)::text, ('Rejected'::character varying)::text, ('Completed'::character varying)::text])))
);


--
-- Name: lesson_plan_headers_lesson_plan_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.lesson_plan_headers_lesson_plan_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lesson_plan_headers_lesson_plan_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.lesson_plan_headers_lesson_plan_id_seq OWNED BY academics.lesson_plan_headers.lesson_plan_id;


--
-- Name: lesson_plan_topic_outcomes; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.lesson_plan_topic_outcomes (
    lesson_plan_topic_id bigint NOT NULL,
    course_outcome_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint
);


--
-- Name: lesson_plan_topics; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.lesson_plan_topics (
    lesson_plan_topic_id bigint NOT NULL,
    lesson_plan_id bigint NOT NULL,
    lesson_number integer NOT NULL,
    topic_description text NOT NULL,
    course_outcome_id bigint NOT NULL,
    lesson_plan_book_id bigint,
    page_from character varying(20),
    page_to character varying(20),
    planned_periods integer DEFAULT 1 NOT NULL,
    planned_date date,
    completion_date date,
    topic_status character varying(20) DEFAULT 'Planned'::character varying NOT NULL,
    remarks text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    ppt_required boolean DEFAULT false NOT NULL,
    video_url text,
    CONSTRAINT lesson_plan_topics_topic_status_check CHECK (((topic_status)::text = ANY (ARRAY[('Planned'::character varying)::text, ('In Progress'::character varying)::text, ('Completed'::character varying)::text, ('Deferred'::character varying)::text])))
);


--
-- Name: lesson_plan_topics_lesson_plan_topic_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.lesson_plan_topics_lesson_plan_topic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lesson_plan_topics_lesson_plan_topic_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.lesson_plan_topics_lesson_plan_topic_id_seq OWNED BY academics.lesson_plan_topics.lesson_plan_topic_id;


--
-- Name: timetable_change_logs; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.timetable_change_logs (
    timetable_change_log_id bigint NOT NULL,
    timetable_id bigint NOT NULL,
    timetable_entry_id bigint,
    action_type character varying(20) NOT NULL,
    old_value jsonb,
    new_value jsonb,
    change_reason text,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT timetable_change_logs_action_type_check CHECK (((action_type)::text = ANY (ARRAY[('Created'::character varying)::text, ('Updated'::character varying)::text, ('Removed'::character varying)::text, ('Published'::character varying)::text, ('Archived'::character varying)::text, ('Copied'::character varying)::text])))
);


--
-- Name: timetable_change_logs_timetable_change_log_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.timetable_change_logs_timetable_change_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timetable_change_logs_timetable_change_log_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.timetable_change_logs_timetable_change_log_id_seq OWNED BY academics.timetable_change_logs.timetable_change_log_id;


--
-- Name: timetable_entries; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.timetable_entries (
    timetable_entry_id bigint NOT NULL,
    timetable_id bigint NOT NULL,
    week_day_id smallint NOT NULL,
    period_id bigint NOT NULL,
    subject_teacher_allocation_id bigint,
    subject_id bigint,
    faculty_employee_id bigint,
    room_id bigint,
    group_id bigint,
    entry_type character varying(20) DEFAULT 'Theory'::character varying NOT NULL,
    display_text character varying(200),
    remarks text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    classroom_id bigint,
    CONSTRAINT timetable_entries_entry_type_check CHECK (((entry_type)::text = ANY (ARRAY[('Theory'::character varying)::text, ('Practical'::character varying)::text, ('Tutorial'::character varying)::text, ('Project'::character varying)::text, ('Seminar'::character varying)::text, ('Library'::character varying)::text, ('Hobby'::character varying)::text, ('Activity'::character varying)::text, ('Other'::character varying)::text])))
);


--
-- Name: timetable_entries_timetable_entry_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.timetable_entries_timetable_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timetable_entries_timetable_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.timetable_entries_timetable_entry_id_seq OWNED BY academics.timetable_entries.timetable_entry_id;


--
-- Name: timetable_headers; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.timetable_headers (
    timetable_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    programme_batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    programme_section_id bigint NOT NULL,
    group_id bigint,
    time_configuration_id bigint NOT NULL,
    timetable_name character varying(200) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    timetable_status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    version_number integer DEFAULT 1 NOT NULL,
    remarks text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    published_by bigint,
    published_at timestamp with time zone,
    CONSTRAINT timetable_headers_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from))),
    CONSTRAINT timetable_headers_timetable_status_check CHECK (((timetable_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Under Review'::character varying)::text, ('Published'::character varying)::text, ('Archived'::character varying)::text]))),
    CONSTRAINT timetable_headers_version_number_check CHECK ((version_number > 0))
);


--
-- Name: timetable_headers_timetable_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.timetable_headers_timetable_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timetable_headers_timetable_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.timetable_headers_timetable_id_seq OWNED BY academics.timetable_headers.timetable_id;


--
-- Name: timetable_working_days; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.timetable_working_days (
    timetable_working_day_id bigint NOT NULL,
    timetable_id bigint NOT NULL,
    week_day_id smallint NOT NULL,
    is_working_day boolean DEFAULT true NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT timetable_working_days_display_order_check CHECK ((display_order > 0))
);


--
-- Name: timetable_working_days_timetable_working_day_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.timetable_working_days_timetable_working_day_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timetable_working_days_timetable_working_day_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.timetable_working_days_timetable_working_day_id_seq OWNED BY academics.timetable_working_days.timetable_working_day_id;


--
-- Name: vw_manage_timetables; Type: VIEW; Schema: academics; Owner: -
--

CREATE VIEW academics.vw_manage_timetables AS
 SELECT timetable_id,
    academic_year_id,
    programme_id,
    programme_batch_id,
    semester_id,
    programme_section_id,
    group_id,
    time_configuration_id,
    timetable_name,
    effective_from,
    effective_to,
    timetable_status,
    version_number,
    created_at,
    updated_at
   FROM academics.timetable_headers th;


--
-- Name: week_days; Type: TABLE; Schema: academics; Owner: -
--

CREATE TABLE academics.week_days (
    week_day_id smallint NOT NULL,
    day_code character varying(10) NOT NULL,
    day_name character varying(20) NOT NULL,
    day_number smallint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT week_days_day_number_check CHECK (((day_number >= 1) AND (day_number <= 7)))
);


--
-- Name: vw_timetable_grid; Type: VIEW; Schema: academics; Owner: -
--

CREATE VIEW academics.vw_timetable_grid AS
 SELECT th.timetable_id,
    wd.week_day_id,
    wd.day_code,
    wd.day_name,
    wd.day_number,
    ap.period_id,
    ap.period_code,
    ap.period_name,
    ap.start_time,
    ap.end_time,
    ap.duration_minutes,
    ap.period_type,
    ap.display_order AS period_display_order,
    ap.is_teaching_period,
    te.timetable_entry_id,
    te.subject_teacher_allocation_id,
    te.subject_id,
    te.faculty_employee_id,
    te.classroom_id AS room_id,
    te.group_id,
    te.entry_type,
    te.display_text,
    te.remarks
   FROM ((((academics.timetable_headers th
     JOIN academics.timetable_working_days twd ON (((twd.timetable_id = th.timetable_id) AND (twd.is_working_day = true))))
     JOIN academics.week_days wd ON ((wd.week_day_id = twd.week_day_id)))
     JOIN academics.academic_periods ap ON (((ap.time_configuration_id = th.time_configuration_id) AND (ap.is_active = true))))
     LEFT JOIN academics.timetable_entries te ON (((te.timetable_id = th.timetable_id) AND (te.week_day_id = wd.week_day_id) AND (te.period_id = ap.period_id))));


--
-- Name: week_days_week_day_id_seq; Type: SEQUENCE; Schema: academics; Owner: -
--

CREATE SEQUENCE academics.week_days_week_day_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: week_days_week_day_id_seq; Type: SEQUENCE OWNED BY; Schema: academics; Owner: -
--

ALTER SEQUENCE academics.week_days_week_day_id_seq OWNED BY academics.week_days.week_day_id;


--
-- Name: sms_batches; Type: TABLE; Schema: communication; Owner: -
--

CREATE TABLE communication.sms_batches (
    sms_batch_id bigint NOT NULL,
    batch_reference character varying(50) NOT NULL,
    recipient_category character varying(30) NOT NULL,
    sms_template_id bigint,
    message_text text NOT NULL,
    language_code character varying(10) DEFAULT 'en'::character varying NOT NULL,
    sender_id character varying(30) DEFAULT 'ABITCLG'::character varying NOT NULL,
    send_type character varying(20) NOT NULL,
    scheduled_at timestamp with time zone,
    batch_status character varying(25) DEFAULT 'Queued'::character varying NOT NULL,
    total_recipients integer DEFAULT 0 NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processed_at timestamp with time zone,
    CONSTRAINT sms_batches_check CHECK ((((send_type)::text = 'Immediate'::text) OR (scheduled_at IS NOT NULL))),
    CONSTRAINT sms_batches_send_type_check CHECK (((send_type)::text = ANY (ARRAY[('Immediate'::character varying)::text, ('Scheduled'::character varying)::text])))
);


--
-- Name: sms_batches_sms_batch_id_seq; Type: SEQUENCE; Schema: communication; Owner: -
--

CREATE SEQUENCE communication.sms_batches_sms_batch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sms_batches_sms_batch_id_seq; Type: SEQUENCE OWNED BY; Schema: communication; Owner: -
--

ALTER SEQUENCE communication.sms_batches_sms_batch_id_seq OWNED BY communication.sms_batches.sms_batch_id;


--
-- Name: sms_recipients; Type: TABLE; Schema: communication; Owner: -
--

CREATE TABLE communication.sms_recipients (
    sms_recipient_id bigint NOT NULL,
    sms_batch_id bigint NOT NULL,
    recipient_type character varying(20) NOT NULL,
    student_id bigint,
    employee_id bigint,
    recipient_name character varying(200) NOT NULL,
    mobile_number character varying(20) NOT NULL,
    personalized_message text NOT NULL,
    sms_parts smallint DEFAULT 1 NOT NULL,
    recipient_status character varying(25) DEFAULT 'Queued'::character varying NOT NULL,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    failure_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT sms_recipients_check CHECK (((student_id IS NOT NULL) OR (employee_id IS NOT NULL))),
    CONSTRAINT sms_recipients_recipient_type_check CHECK (((recipient_type)::text = ANY (ARRAY[('Student'::character varying)::text, ('Guardian'::character varying)::text, ('Employee'::character varying)::text]))),
    CONSTRAINT sms_recipients_sms_parts_check CHECK ((sms_parts > 0))
);


--
-- Name: sms_recipients_sms_recipient_id_seq; Type: SEQUENCE; Schema: communication; Owner: -
--

CREATE SEQUENCE communication.sms_recipients_sms_recipient_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sms_recipients_sms_recipient_id_seq; Type: SEQUENCE OWNED BY; Schema: communication; Owner: -
--

ALTER SEQUENCE communication.sms_recipients_sms_recipient_id_seq OWNED BY communication.sms_recipients.sms_recipient_id;


--
-- Name: sms_templates; Type: TABLE; Schema: communication; Owner: -
--

CREATE TABLE communication.sms_templates (
    sms_template_id bigint NOT NULL,
    template_name character varying(150) NOT NULL,
    template_code character varying(50) NOT NULL,
    recipient_type character varying(20) NOT NULL,
    template_message text NOT NULL,
    language_code character varying(10) DEFAULT 'en'::character varying NOT NULL,
    is_unicode boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT sms_templates_recipient_type_check CHECK (((recipient_type)::text = ANY (ARRAY[('Student'::character varying)::text, ('Guardian'::character varying)::text, ('Employee'::character varying)::text, ('General'::character varying)::text])))
);


--
-- Name: sms_templates_sms_template_id_seq; Type: SEQUENCE; Schema: communication; Owner: -
--

CREATE SEQUENCE communication.sms_templates_sms_template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sms_templates_sms_template_id_seq; Type: SEQUENCE OWNED BY; Schema: communication; Owner: -
--

ALTER SEQUENCE communication.sms_templates_sms_template_id_seq OWNED BY communication.sms_templates.sms_template_id;


--
-- Name: communication_modes; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.communication_modes (
    communication_mode_id bigint NOT NULL,
    mode_code character varying(30) NOT NULL,
    mode_name character varying(100) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: communication_modes_communication_mode_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.communication_modes_communication_mode_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: communication_modes_communication_mode_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.communication_modes_communication_mode_id_seq OWNED BY mentoring.communication_modes.communication_mode_id;


--
-- Name: counselling_followups; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.counselling_followups (
    counselling_followup_id bigint NOT NULL,
    student_counselling_id bigint NOT NULL,
    followup_date date DEFAULT CURRENT_DATE NOT NULL,
    followup_type character varying(30) NOT NULL,
    followup_details text NOT NULL,
    action_taken text,
    assigned_to_employee_id bigint,
    next_followup_date date,
    followup_status character varying(20) DEFAULT 'Pending'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT counselling_followups_check CHECK (((next_followup_date IS NULL) OR (next_followup_date >= followup_date))),
    CONSTRAINT counselling_followups_followup_status_check CHECK (((followup_status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('In Progress'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
    CONSTRAINT counselling_followups_followup_type_check CHECK (((followup_type)::text = ANY (ARRAY[('Mentor Follow-up'::character varying)::text, ('Reviewer Follow-up'::character varying)::text, ('Parent Contact'::character varying)::text, ('Academic Support'::character varying)::text, ('Attendance Warning'::character varying)::text, ('Other'::character varying)::text])))
);


--
-- Name: counselling_followups_counselling_followup_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.counselling_followups_counselling_followup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: counselling_followups_counselling_followup_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.counselling_followups_counselling_followup_id_seq OWNED BY mentoring.counselling_followups.counselling_followup_id;


--
-- Name: counselling_purposes; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.counselling_purposes (
    counselling_purpose_id bigint NOT NULL,
    purpose_code character varying(30) NOT NULL,
    purpose_name character varying(100) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: counselling_purposes_counselling_purpose_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.counselling_purposes_counselling_purpose_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: counselling_purposes_counselling_purpose_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.counselling_purposes_counselling_purpose_id_seq OWNED BY mentoring.counselling_purposes.counselling_purpose_id;


--
-- Name: counselling_reviewer_remarks; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.counselling_reviewer_remarks (
    counselling_reviewer_remark_id bigint NOT NULL,
    student_counselling_id bigint NOT NULL,
    reviewer_id bigint NOT NULL,
    reviewer_level character varying(20) NOT NULL,
    review_date date DEFAULT CURRENT_DATE NOT NULL,
    reviewer_remarks text NOT NULL,
    recommendation text,
    follow_up_required boolean DEFAULT false NOT NULL,
    next_review_date date,
    review_status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT counselling_reviewer_remarks_check CHECK (((next_review_date IS NULL) OR (next_review_date >= review_date))),
    CONSTRAINT counselling_reviewer_remarks_review_status_check CHECK (((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text, ('Closed'::character varying)::text]))),
    CONSTRAINT counselling_reviewer_remarks_reviewer_level_check CHECK (((reviewer_level)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);


--
-- Name: counselling_reviewer_remarks_counselling_reviewer_remark_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.counselling_reviewer_remarks_counselling_reviewer_remark_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: counselling_reviewer_remarks_counselling_reviewer_remark_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.counselling_reviewer_remarks_counselling_reviewer_remark_id_seq OWNED BY mentoring.counselling_reviewer_remarks.counselling_reviewer_remark_id;


--
-- Name: employee_mentor_eligibility; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.employee_mentor_eligibility (
    employee_mentor_eligibility_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    is_mentor_for_new_students boolean DEFAULT false NOT NULL,
    maximum_students integer DEFAULT 30 NOT NULL,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    eligibility_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    remarks text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT employee_mentor_eligibility_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from))),
    CONSTRAINT employee_mentor_eligibility_eligibility_status_check CHECK (((eligibility_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Suspended'::character varying)::text]))),
    CONSTRAINT employee_mentor_eligibility_maximum_students_check CHECK ((maximum_students > 0))
);


--
-- Name: employee_mentor_eligibility_employee_mentor_eligibility_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.employee_mentor_eligibility_employee_mentor_eligibility_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_mentor_eligibility_employee_mentor_eligibility_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.employee_mentor_eligibility_employee_mentor_eligibility_id_seq OWNED BY mentoring.employee_mentor_eligibility.employee_mentor_eligibility_id;


--
-- Name: employee_mentor_eligibility_history; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.employee_mentor_eligibility_history (
    employee_mentor_eligibility_history_id bigint NOT NULL,
    employee_mentor_eligibility_id bigint NOT NULL,
    old_is_mentor boolean,
    new_is_mentor boolean NOT NULL,
    old_maximum_students integer,
    new_maximum_students integer,
    change_reason text,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: employee_mentor_eligibility_h_employee_mentor_eligibility_h_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.employee_mentor_eligibility_h_employee_mentor_eligibility_h_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_mentor_eligibility_h_employee_mentor_eligibility_h_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.employee_mentor_eligibility_h_employee_mentor_eligibility_h_seq OWNED BY mentoring.employee_mentor_eligibility_history.employee_mentor_eligibility_history_id;


--
-- Name: first_reviewer_remarks; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.first_reviewer_remarks (
    first_reviewer_remark_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    student_id bigint NOT NULL,
    mentor_id bigint NOT NULL,
    reviewer_id bigint NOT NULL,
    mentor_reviewer_allotment_id bigint,
    review_date date DEFAULT CURRENT_DATE NOT NULL,
    information_entered text,
    first_reviewer_remarks text NOT NULL,
    grading_to_mentor character varying(30),
    suggestion_to_mentor text,
    follow_up_required boolean DEFAULT false NOT NULL,
    next_review_date date,
    review_status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT first_reviewer_remarks_check CHECK (((next_review_date IS NULL) OR (next_review_date >= review_date))),
    CONSTRAINT first_reviewer_remarks_grading_to_mentor_check CHECK (((grading_to_mentor IS NULL) OR ((grading_to_mentor)::text = ANY (ARRAY[('Excellent'::character varying)::text, ('Very Good'::character varying)::text, ('Good'::character varying)::text, ('Average'::character varying)::text, ('Needs Improvement'::character varying)::text, ('Unsatisfactory'::character varying)::text])))),
    CONSTRAINT first_reviewer_remarks_review_status_check CHECK (((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text, ('Closed'::character varying)::text])))
);


--
-- Name: first_reviewer_remarks_first_reviewer_remark_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.first_reviewer_remarks_first_reviewer_remark_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: first_reviewer_remarks_first_reviewer_remark_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.first_reviewer_remarks_first_reviewer_remark_id_seq OWNED BY mentoring.first_reviewer_remarks.first_reviewer_remark_id;


--
-- Name: mentor_assignment_changes; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.mentor_assignment_changes (
    assignment_change_id bigint NOT NULL,
    student_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    previous_mentor_id bigint,
    mentor_id bigint NOT NULL,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: mentor_assignment_changes_assignment_change_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.mentor_assignment_changes_assignment_change_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentor_assignment_changes_assignment_change_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.mentor_assignment_changes_assignment_change_id_seq OWNED BY mentoring.mentor_assignment_changes.assignment_change_id;


--
-- Name: mentor_reviewer_allotment_details; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.mentor_reviewer_allotment_details (
    mentor_reviewer_detail_id bigint NOT NULL,
    mentor_reviewer_allotment_id bigint NOT NULL,
    reviewer_id bigint NOT NULL,
    reviewer_role character varying(20) NOT NULL,
    display_order smallint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    assigned_from date DEFAULT CURRENT_DATE NOT NULL,
    assigned_to date,
    remarks text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT mentor_reviewer_allotment_details_check CHECK (((assigned_to IS NULL) OR (assigned_to >= assigned_from))),
    CONSTRAINT mentor_reviewer_allotment_details_display_order_check CHECK (((display_order >= 1) AND (display_order <= 3))),
    CONSTRAINT mentor_reviewer_allotment_details_reviewer_role_check CHECK (((reviewer_role)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);


--
-- Name: mentor_reviewer_allotment_details_mentor_reviewer_detail_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.mentor_reviewer_allotment_details_mentor_reviewer_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentor_reviewer_allotment_details_mentor_reviewer_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.mentor_reviewer_allotment_details_mentor_reviewer_detail_id_seq OWNED BY mentoring.mentor_reviewer_allotment_details.mentor_reviewer_detail_id;


--
-- Name: mentor_reviewer_allotments; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.mentor_reviewer_allotments (
    mentor_reviewer_allotment_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    department_id bigint,
    mentor_id bigint NOT NULL,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    allotment_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    remarks text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT mentor_reviewer_allotments_allotment_status_check CHECK (((allotment_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
    CONSTRAINT mentor_reviewer_allotments_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);


--
-- Name: mentor_reviewer_allotments_mentor_reviewer_allotment_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.mentor_reviewer_allotments_mentor_reviewer_allotment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentor_reviewer_allotments_mentor_reviewer_allotment_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.mentor_reviewer_allotments_mentor_reviewer_allotment_id_seq OWNED BY mentoring.mentor_reviewer_allotments.mentor_reviewer_allotment_id;


--
-- Name: mentor_reviewer_change_history; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.mentor_reviewer_change_history (
    mentor_reviewer_change_id bigint NOT NULL,
    mentor_reviewer_allotment_id bigint NOT NULL,
    reviewer_role character varying(20) NOT NULL,
    old_reviewer_id bigint,
    new_reviewer_id bigint,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    change_reason text NOT NULL,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT mentor_reviewer_change_history_reviewer_role_check CHECK (((reviewer_role)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);


--
-- Name: mentor_reviewer_change_history_mentor_reviewer_change_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.mentor_reviewer_change_history_mentor_reviewer_change_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentor_reviewer_change_history_mentor_reviewer_change_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.mentor_reviewer_change_history_mentor_reviewer_change_id_seq OWNED BY mentoring.mentor_reviewer_change_history.mentor_reviewer_change_id;


--
-- Name: mentors; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.mentors (
    mentor_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    department_id bigint,
    maximum_students integer DEFAULT 30 NOT NULL,
    mentor_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    created_by bigint,
    updated_by bigint,
    updated_at timestamp with time zone,
    employee_mentor_eligibility_id bigint,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    CONSTRAINT mentors_effective_dates_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);


--
-- Name: mentors_mentor_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.mentors_mentor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentors_mentor_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.mentors_mentor_id_seq OWNED BY mentoring.mentors.mentor_id;


--
-- Name: parent_interactions; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.parent_interactions (
    parent_interaction_id bigint NOT NULL,
    student_id bigint NOT NULL,
    mentor_id bigint NOT NULL,
    student_counselling_id bigint,
    interaction_date date DEFAULT CURRENT_DATE NOT NULL,
    parent_name character varying(150),
    relationship character varying(50),
    parent_contact_number character varying(20),
    communication_mode character varying(30) NOT NULL,
    discussion_details text NOT NULL,
    parent_commitment text,
    action_required text,
    next_contact_date date,
    interaction_status character varying(20) DEFAULT 'Completed'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT parent_interactions_check CHECK (((next_contact_date IS NULL) OR (next_contact_date >= interaction_date))),
    CONSTRAINT parent_interactions_communication_mode_check CHECK (((communication_mode)::text = ANY (ARRAY[('Over Phone'::character varying)::text, ('Formal Meeting'::character varying)::text, ('Online Meeting'::character varying)::text, ('Email'::character varying)::text, ('WhatsApp'::character varying)::text, ('Other'::character varying)::text]))),
    CONSTRAINT parent_interactions_interaction_status_check CHECK (((interaction_status)::text = ANY (ARRAY[('Scheduled'::character varying)::text, ('Completed'::character varying)::text, ('Follow-up'::character varying)::text, ('Cancelled'::character varying)::text])))
);


--
-- Name: parent_interactions_parent_interaction_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.parent_interactions_parent_interaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: parent_interactions_parent_interaction_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.parent_interactions_parent_interaction_id_seq OWNED BY mentoring.parent_interactions.parent_interaction_id;


--
-- Name: prospective_student_mentor_allotments; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.prospective_student_mentor_allotments (
    prospective_student_mentor_allotment_id bigint NOT NULL,
    prospective_student_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    allotted_from date DEFAULT CURRENT_DATE NOT NULL,
    allotted_to date,
    allotment_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    change_reason text,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT prospective_student_mentor_allotments_allotment_status_check CHECK (((allotment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Changed'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
    CONSTRAINT prospective_student_mentor_allotments_check CHECK (((allotted_to IS NULL) OR (allotted_to >= allotted_from)))
);


--
-- Name: prospective_student_mentor_al_prospective_student_mentor_al_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.prospective_student_mentor_al_prospective_student_mentor_al_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prospective_student_mentor_al_prospective_student_mentor_al_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.prospective_student_mentor_al_prospective_student_mentor_al_seq OWNED BY mentoring.prospective_student_mentor_allotments.prospective_student_mentor_allotment_id;


--
-- Name: reviewers; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.reviewers (
    reviewer_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: reviewers_reviewer_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.reviewers_reviewer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reviewers_reviewer_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.reviewers_reviewer_id_seq OWNED BY mentoring.reviewers.reviewer_id;


--
-- Name: student_counsellings; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.student_counsellings (
    student_counselling_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    student_id bigint NOT NULL,
    mentor_id bigint NOT NULL,
    discussion_date date DEFAULT CURRENT_DATE NOT NULL,
    communication_mode character varying(30) NOT NULL,
    purpose character varying(100) NOT NULL,
    detailed_discussion text NOT NULL,
    mentor_remarks text,
    follow_up_required boolean DEFAULT false NOT NULL,
    next_follow_up_date date,
    counselling_status character varying(20) DEFAULT 'Open'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    programme_id bigint,
    programme_batch_id bigint,
    semester_id bigint,
    programme_section_id bigint,
    communication_mode_id bigint,
    counselling_purpose_id bigint,
    confidentiality_level character varying(20) DEFAULT 'Normal'::character varying NOT NULL,
    CONSTRAINT student_counsellings_check CHECK (((next_follow_up_date IS NULL) OR (next_follow_up_date >= discussion_date))),
    CONSTRAINT student_counsellings_communication_mode_check CHECK (((communication_mode)::text = ANY (ARRAY[('Over Phone'::character varying)::text, ('Formal Meeting'::character varying)::text, ('Online Meeting'::character varying)::text, ('Parent Meeting'::character varying)::text, ('Email'::character varying)::text, ('WhatsApp'::character varying)::text, ('Home Visit'::character varying)::text, ('Other'::character varying)::text]))),
    CONSTRAINT student_counsellings_confidentiality_level_check CHECK (((confidentiality_level)::text = ANY (ARRAY[('Normal'::character varying)::text, ('Restricted'::character varying)::text, ('Confidential'::character varying)::text]))),
    CONSTRAINT student_counsellings_counselling_status_check CHECK (((counselling_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Open'::character varying)::text, ('Follow-up'::character varying)::text, ('Resolved'::character varying)::text, ('Closed'::character varying)::text])))
);


--
-- Name: student_counsellings_student_counselling_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.student_counsellings_student_counselling_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_counsellings_student_counselling_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.student_counsellings_student_counselling_id_seq OWNED BY mentoring.student_counsellings.student_counselling_id;


--
-- Name: student_mentor_allotments; Type: TABLE; Schema: mentoring; Owner: -
--

CREATE TABLE mentoring.student_mentor_allotments (
    mentor_allotment_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    student_id bigint NOT NULL,
    mentor_id bigint NOT NULL,
    programme_id bigint,
    programme_batch_id bigint,
    semester_id bigint,
    programme_section_id bigint,
    allotted_from date DEFAULT CURRENT_DATE NOT NULL,
    allotted_to date,
    allotment_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    change_reason text,
    CONSTRAINT student_mentor_allotments_allotment_status_check CHECK (((allotment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Changed'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
    CONSTRAINT student_mentor_allotments_check CHECK (((allotted_to IS NULL) OR (allotted_to >= allotted_from)))
);


--
-- Name: student_mentor_allotments_mentor_allotment_id_seq; Type: SEQUENCE; Schema: mentoring; Owner: -
--

CREATE SEQUENCE mentoring.student_mentor_allotments_mentor_allotment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentor_allotments_mentor_allotment_id_seq; Type: SEQUENCE OWNED BY; Schema: mentoring; Owner: -
--

ALTER SEQUENCE mentoring.student_mentor_allotments_mentor_allotment_id_seq OWNED BY mentoring.student_mentor_allotments.mentor_allotment_id;


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    employee_id bigint NOT NULL,
    user_id bigint,
    institution_id bigint NOT NULL,
    department_id bigint,
    designation_id bigint,
    employee_code character varying(30) NOT NULL,
    first_name character varying(80) NOT NULL,
    middle_name character varying(80),
    last_name character varying(80),
    gender character varying(20),
    date_of_birth date,
    date_of_joining date,
    employment_type character varying(30),
    qualification character varying(200),
    specialization character varying(200),
    official_email character varying(150),
    personal_email character varying(150),
    mobile character varying(20),
    address text,
    photo_url text,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    blood_group character varying(10),
    marital_status character varying(20),
    alternate_mobile character varying(20),
    permanent_address text,
    aadhaar_number character varying(20),
    pan_number character varying(20),
    employee_category character varying(40),
    campus_id bigint,
    reporting_employee_id bigint,
    bank_name character varying(150),
    bank_account_number character varying(50),
    bank_ifsc character varying(20),
    bank_branch character varying(150),
    document_names jsonb DEFAULT '[]'::jsonb NOT NULL,
    deleted_at timestamp with time zone,
    profile_details jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.students (
    student_id bigint NOT NULL,
    user_id bigint,
    institution_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    section_id bigint,
    registration_no character varying(50),
    roll_no character varying(50),
    admission_no character varying(50) NOT NULL,
    first_name character varying(80) NOT NULL,
    middle_name character varying(80),
    last_name character varying(80),
    gender character varying(20),
    date_of_birth date,
    category character varying(30),
    blood_group character varying(10),
    mobile character varying(20),
    email character varying(150),
    permanent_address text,
    current_address text,
    admission_date date,
    admission_type character varying(30),
    lateral_entry boolean DEFAULT false NOT NULL,
    photo_url text,
    status character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    institute_id bigint NOT NULL,
    campus_id bigint,
    academic_year_id bigint,
    department_id bigint,
    semester_id bigint,
    admission_category_id bigint,
    student_status_id bigint,
    admission_type_value_id bigint,
    gender_value_id bigint,
    blood_group_value_id bigint,
    religion_value_id bigint,
    category_value_id bigint,
    admission_number character varying(50),
    student_code character varying(40) NOT NULL,
    registration_number character varying(60),
    university_registration_number character varying(60),
    roll_number character varying(50),
    mobile_number character varying(20),
    alternate_mobile_number character varying(20),
    aadhaar_number character varying(20),
    profile_photo_url character varying(500),
    profile_photo_name character varying(255),
    profile_photo_mime_type character varying(100),
    profile_photo_size bigint,
    is_active boolean DEFAULT true NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by bigint,
    deletion_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    branch_id bigint,
    student_profile_details jsonb DEFAULT '{}'::jsonb NOT NULL,
    student_group character varying(30)
);


--
-- Name: vw_first_reviewer_remarks; Type: VIEW; Schema: mentoring; Owner: -
--

CREATE VIEW mentoring.vw_first_reviewer_remarks AS
 SELECT frr.first_reviewer_remark_id,
    frr.academic_year_id,
    frr.student_id,
    COALESCE(NULLIF((s.registration_number)::text, ''::text), NULLIF((s.registration_no)::text, ''::text), (s.student_code)::text) AS registration_no,
    TRIM(BOTH FROM concat_ws(' '::text, s.first_name, s.middle_name, s.last_name)) AS student_name,
    frr.mentor_id,
    TRIM(BOTH FROM concat_ws(' '::text, me.first_name, me.middle_name, me.last_name)) AS mentor_name,
    frr.reviewer_id,
    TRIM(BOTH FROM concat_ws(' '::text, re.first_name, re.middle_name, re.last_name)) AS first_reviewer_name,
    frr.mentor_reviewer_allotment_id,
    frr.information_entered,
    frr.first_reviewer_remarks,
    frr.grading_to_mentor,
    frr.suggestion_to_mentor,
    frr.follow_up_required,
    frr.next_review_date,
    frr.review_status,
    frr.review_date
   FROM ((((mentoring.first_reviewer_remarks frr
     JOIN public.students s ON ((s.student_id = frr.student_id)))
     JOIN mentoring.mentors m ON ((m.mentor_id = frr.mentor_id)))
     JOIN public.employees me ON ((me.employee_id = m.employee_id)))
     JOIN public.employees re ON ((re.employee_id = frr.reviewer_id)));


--
-- Name: vw_mentor_allotment_report; Type: VIEW; Schema: mentoring; Owner: -
--

CREATE VIEW mentoring.vw_mentor_allotment_report AS
SELECT
    NULL::bigint AS employee_id,
    NULL::bigint AS mentor_id,
    NULL::character varying(80) AS first_name,
    NULL::character varying(80) AS middle_name,
    NULL::character varying(80) AS last_name,
    NULL::character varying(150) AS department_name,
    NULL::character varying(100) AS designation_name,
    NULL::text AS category_name,
    NULL::integer AS maximum_students,
    NULL::integer AS students_allotted,
    NULL::integer AS available_capacity,
    NULL::character varying AS mentor_status;


--
-- Name: vw_student_counsellings_reviews; Type: VIEW; Schema: mentoring; Owner: -
--

CREATE VIEW mentoring.vw_student_counsellings_reviews AS
SELECT
    NULL::bigint AS student_counselling_id,
    NULL::bigint AS academic_year_id,
    NULL::bigint AS student_id,
    NULL::bigint AS mentor_id,
    NULL::date AS discussion_date,
    NULL::character varying AS communication_mode,
    NULL::character varying(100) AS purpose,
    NULL::text AS detailed_discussion,
    NULL::text AS mentor_remarks,
    NULL::character varying(20) AS counselling_status,
    NULL::text AS reviewer_1_remarks,
    NULL::text AS reviewer_2_remarks,
    NULL::text AS chief_reviewer_remarks;


--
-- Name: vw_students_under_mentorship; Type: VIEW; Schema: mentoring; Owner: -
--

CREATE VIEW mentoring.vw_students_under_mentorship AS
 SELECT sma.academic_year_id,
    sma.mentor_id,
    s.student_id,
    COALESCE(NULLIF((s.registration_number)::text, ''::text), NULLIF((s.registration_no)::text, ''::text), (s.student_code)::text) AS registration_no,
    TRIM(BOTH FROM concat_ws(' '::text, s.first_name, s.middle_name, s.last_name)) AS student_name,
    COALESCE(NULLIF((s.mobile_number)::text, ''::text), (s.mobile)::text) AS student_contact_number,
    count(DISTINCT sc.student_counselling_id) AS total_student_counsellings,
    count(DISTINCT sc.student_counselling_id) FILTER (WHERE (sc.discussion_date >= (CURRENT_DATE - '15 days'::interval))) AS counsellings_last_15_days,
    max(sc.discussion_date) AS last_counselled_on,
    count(DISTINCT pi.parent_interaction_id) AS total_guardian_discussions,
    count(DISTINCT pi.parent_interaction_id) FILTER (WHERE (pi.interaction_date >= (CURRENT_DATE - '30 days'::interval))) AS guardian_discussions_last_30_days,
    max(pi.interaction_date) AS last_guardian_contact_on
   FROM (((mentoring.student_mentor_allotments sma
     JOIN public.students s ON ((s.student_id = sma.student_id)))
     LEFT JOIN mentoring.student_counsellings sc ON (((sc.student_id = s.student_id) AND (sc.mentor_id = sma.mentor_id))))
     LEFT JOIN mentoring.parent_interactions pi ON (((pi.student_id = s.student_id) AND (pi.mentor_id = sma.mentor_id))))
  WHERE ((sma.allotment_status)::text = 'Active'::text)
  GROUP BY sma.academic_year_id, sma.mentor_id, s.student_id, s.registration_number, s.registration_no, s.student_code, s.first_name, s.middle_name, s.last_name, s.mobile_number, s.mobile;


--
-- Name: permission_change_history; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.permission_change_history (
    history_id bigint NOT NULL,
    user_id bigint,
    role_id bigint,
    menu_id bigint,
    permission_id bigint,
    old_value boolean,
    new_value boolean,
    action_type character varying(30) NOT NULL,
    changed_by bigint,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    remarks character varying(500),
    CONSTRAINT permission_change_history_action_type_check CHECK (((action_type)::text = ANY ((ARRAY['GRANT'::character varying, 'REVOKE'::character varying, 'ROLE_ASSIGN'::character varying, 'ROLE_REMOVE'::character varying])::text[])))
);


--
-- Name: permission_change_history_history_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.permission_change_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permission_change_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.permission_change_history_history_id_seq OWNED BY permission_management.permission_change_history.history_id;


--
-- Name: permissions; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.permissions (
    permission_id bigint NOT NULL,
    permission_code character varying(40) NOT NULL,
    permission_name character varying(80) NOT NULL,
    description character varying(250),
    status boolean DEFAULT true NOT NULL
);


--
-- Name: permissions_permission_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.permissions_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.permissions_permission_id_seq OWNED BY permission_management.permissions.permission_id;


--
-- Name: role_permissions; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.role_permissions (
    role_permission_id bigint NOT NULL,
    role_id bigint NOT NULL,
    menu_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    is_allowed boolean DEFAULT true NOT NULL,
    granted_by bigint,
    granted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: role_permissions_role_permission_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.role_permissions_role_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_permissions_role_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.role_permissions_role_permission_id_seq OWNED BY permission_management.role_permissions.role_permission_id;


--
-- Name: roles; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.roles (
    role_id bigint NOT NULL,
    role_code character varying(50) NOT NULL,
    role_name character varying(100) NOT NULL,
    description character varying(300),
    is_system_role boolean DEFAULT false NOT NULL,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: roles_role_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.roles_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_role_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.roles_role_id_seq OWNED BY permission_management.roles.role_id;


--
-- Name: system_menus; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.system_menus (
    menu_id bigint NOT NULL,
    module_id bigint NOT NULL,
    parent_menu_id bigint,
    menu_code character varying(80) NOT NULL,
    menu_name character varying(120) NOT NULL,
    menu_path character varying(250),
    menu_icon character varying(100),
    display_order integer DEFAULT 0,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: system_menus_menu_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.system_menus_menu_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_menus_menu_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.system_menus_menu_id_seq OWNED BY permission_management.system_menus.menu_id;


--
-- Name: system_modules; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.system_modules (
    module_id bigint NOT NULL,
    module_code character varying(50) NOT NULL,
    module_name character varying(100) NOT NULL,
    module_icon character varying(100),
    display_order integer DEFAULT 0,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: system_modules_module_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.system_modules_module_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_modules_module_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.system_modules_module_id_seq OWNED BY permission_management.system_modules.module_id;


--
-- Name: user_permissions; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.user_permissions (
    user_permission_id bigint NOT NULL,
    user_id bigint NOT NULL,
    menu_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    is_allowed boolean NOT NULL,
    valid_from timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    valid_to timestamp without time zone,
    remarks character varying(500),
    granted_by bigint,
    granted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_permissions_user_permission_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.user_permissions_user_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_permissions_user_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.user_permissions_user_permission_id_seq OWNED BY permission_management.user_permissions.user_permission_id;


--
-- Name: user_roles; Type: TABLE; Schema: permission_management; Owner: -
--

CREATE TABLE permission_management.user_roles (
    user_role_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    department_id bigint,
    valid_from date DEFAULT CURRENT_DATE,
    valid_to date,
    status boolean DEFAULT true NOT NULL,
    assigned_by bigint,
    assigned_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_roles_user_role_id_seq; Type: SEQUENCE; Schema: permission_management; Owner: -
--

CREATE SEQUENCE permission_management.user_roles_user_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_roles_user_role_id_seq; Type: SEQUENCE OWNED BY; Schema: permission_management; Owner: -
--

ALTER SEQUENCE permission_management.user_roles_user_role_id_seq OWNED BY permission_management.user_roles.user_role_id;


--
-- Name: academic_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.academic_terms (
    term_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    term_name character varying(50) NOT NULL,
    term_type character varying(20) DEFAULT 'SEMESTER'::character varying NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status character varying(20) DEFAULT 'PLANNED'::character varying NOT NULL,
    CONSTRAINT academic_terms_check CHECK ((end_date > start_date))
);


--
-- Name: academic_terms_term_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.academic_terms_term_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: academic_terms_term_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.academic_terms_term_id_seq OWNED BY public.academic_terms.term_id;


--
-- Name: academic_years; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.academic_years (
    academic_year_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    year_label character varying(20) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    is_current boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    academic_year_name character varying(120),
    admission_start_date date,
    admission_end_date date,
    allow_data_entry boolean DEFAULT true NOT NULL,
    allow_previous_year_edit boolean DEFAULT false NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    CONSTRAINT academic_years_check CHECK ((end_date > start_date))
);


--
-- Name: academic_years_academic_year_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.academic_years_academic_year_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: academic_years_academic_year_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.academic_years_academic_year_id_seq OWNED BY public.academic_years.academic_year_id;


--
-- Name: admission_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admission_batches (
    batch_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    admission_year smallint NOT NULL,
    batch_name character varying(100) NOT NULL,
    start_date date,
    expected_end_date date,
    actual_end_date date,
    is_active boolean DEFAULT true NOT NULL,
    batch_alias character varying(50),
    approved_intake integer DEFAULT 0 NOT NULL,
    lateral_entry_intake integer DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL
);


--
-- Name: admission_batches_batch_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admission_batches_batch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admission_batches_batch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admission_batches_batch_id_seq OWNED BY public.admission_batches.batch_id;


--
-- Name: admission_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admission_categories (
    admission_category_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    category_code character varying(30) NOT NULL,
    category_name character varying(120) NOT NULL,
    reservation_percentage numeric(5,2),
    scholarship_eligible boolean DEFAULT false NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT admission_categories_reservation_percentage_check CHECK (((reservation_percentage IS NULL) OR ((reservation_percentage >= (0)::numeric) AND (reservation_percentage <= (100)::numeric))))
);


--
-- Name: admission_categories_admission_category_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admission_categories_admission_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admission_categories_admission_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admission_categories_admission_category_id_seq OWNED BY public.admission_categories.admission_category_id;


--
-- Name: approval_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_actions (
    approval_action_id bigint NOT NULL,
    approval_request_id bigint NOT NULL,
    action_by bigint NOT NULL,
    action character varying(20) NOT NULL,
    remarks text,
    action_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: approval_actions_approval_action_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_actions_approval_action_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_actions_approval_action_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_actions_approval_action_id_seq OWNED BY public.approval_actions.approval_action_id;


--
-- Name: approval_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_requests (
    approval_request_id bigint NOT NULL,
    request_type character varying(50) NOT NULL,
    reference_table character varying(80) NOT NULL,
    reference_id bigint NOT NULL,
    requested_by bigint NOT NULL,
    current_approver_id bigint,
    current_level integer DEFAULT 1 NOT NULL,
    status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL,
    remarks text,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);


--
-- Name: approval_requests_approval_request_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_requests_approval_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_requests_approval_request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_requests_approval_request_id_seq OWNED BY public.approval_requests.approval_request_id;


--
-- Name: assessment_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment_components (
    assessment_id bigint NOT NULL,
    offering_id bigint NOT NULL,
    examination_id bigint,
    component_name character varying(100) NOT NULL,
    component_type character varying(30) NOT NULL,
    maximum_marks numeric(7,2) NOT NULL,
    pass_marks numeric(7,2),
    weightage numeric(5,2),
    assessment_date date
);


--
-- Name: assessment_components_assessment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assessment_components_assessment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assessment_components_assessment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assessment_components_assessment_id_seq OWNED BY public.assessment_components.assessment_id;


--
-- Name: attendance_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_sessions (
    attendance_session_id bigint NOT NULL,
    offering_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    attendance_date date NOT NULL,
    time_slot_id bigint,
    topic_covered text,
    delivery_mode character varying(20) DEFAULT 'OFFLINE'::character varying,
    session_status character varying(20) DEFAULT 'COMPLETED'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: attendance_sessions_attendance_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.attendance_sessions_attendance_session_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attendance_sessions_attendance_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.attendance_sessions_attendance_session_id_seq OWNED BY public.attendance_sessions.attendance_session_id;


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    audit_log_id bigint NOT NULL,
    user_id bigint,
    action_type character varying(30) NOT NULL,
    table_name character varying(100),
    record_id bigint,
    old_values jsonb,
    new_values jsonb,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_logs_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_audit_log_id_seq OWNED BY public.audit_logs.audit_log_id;


--
-- Name: batch_section_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.batch_section_assignments (
    assignment_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    section_master_id bigint NOT NULL,
    initial_section_id bigint,
    intake integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT batch_section_assignments_intake_check CHECK ((intake > 0))
);


--
-- Name: batch_section_assignments_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.batch_section_assignments_assignment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: batch_section_assignments_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.batch_section_assignments_assignment_id_seq OWNED BY public.batch_section_assignments.assignment_id;


--
-- Name: batch_survey_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.batch_survey_settings (
    batch_id bigint NOT NULL,
    annual_survey_eligible boolean DEFAULT false NOT NULL,
    exit_survey_eligible boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: building_departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.building_departments (
    building_id bigint NOT NULL,
    department_id bigint NOT NULL
);


--
-- Name: buildings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.buildings (
    building_id bigint NOT NULL,
    campus_id bigint NOT NULL,
    building_code character varying(30) NOT NULL,
    building_name character varying(100) NOT NULL
);


--
-- Name: buildings_building_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.buildings_building_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: buildings_building_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.buildings_building_id_seq OWNED BY public.buildings.building_id;


--
-- Name: campuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campuses (
    campus_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    campus_code character varying(30) NOT NULL,
    campus_name character varying(150) NOT NULL,
    address text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: campuses_campus_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.campuses_campus_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campuses_campus_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.campuses_campus_id_seq OWNED BY public.campuses.campus_id;


--
-- Name: class_teacher_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.class_teacher_allocations (
    class_teacher_allocation_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    section_id bigint NOT NULL,
    student_group character varying(30) DEFAULT 'ALL'::character varying NOT NULL,
    employee_id bigint NOT NULL,
    teacher_type character varying(20) DEFAULT 'MAIN'::character varying NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    subject_master_id bigint
);


--
-- Name: class_teacher_allocations_class_teacher_allocation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.class_teacher_allocations_class_teacher_allocation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: class_teacher_allocations_class_teacher_allocation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.class_teacher_allocations_class_teacher_allocation_id_seq OWNED BY public.class_teacher_allocations.class_teacher_allocation_id;


--
-- Name: classroom_facilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classroom_facilities (
    classroom_id bigint NOT NULL,
    facility_id bigint NOT NULL
);


--
-- Name: classroom_facility_masters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classroom_facility_masters (
    facility_id bigint NOT NULL,
    facility_code character varying(30) NOT NULL,
    facility_name character varying(100) NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: classroom_facility_masters_facility_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.classroom_facility_masters_facility_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: classroom_facility_masters_facility_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.classroom_facility_masters_facility_id_seq OWNED BY public.classroom_facility_masters.facility_id;


--
-- Name: classroom_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classroom_types (
    classroom_type_id bigint NOT NULL,
    classroom_type_code character varying(30) NOT NULL,
    classroom_type_name character varying(100) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: classroom_types_classroom_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.classroom_types_classroom_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: classroom_types_classroom_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.classroom_types_classroom_type_id_seq OWNED BY public.classroom_types.classroom_type_id;


--
-- Name: classroom_unavailability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classroom_unavailability (
    classroom_unavailability_id bigint NOT NULL,
    classroom_id bigint NOT NULL,
    unavailable_date date,
    week_day_id smallint,
    period_id bigint,
    unavailable_from timestamp with time zone,
    unavailable_to timestamp with time zone,
    reason character varying(250) NOT NULL,
    unavailability_type character varying(30) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT classroom_unavailability_check CHECK (((unavailable_to IS NULL) OR (unavailable_from IS NULL) OR (unavailable_to > unavailable_from))),
    CONSTRAINT classroom_unavailability_unavailability_type_check CHECK (((unavailability_type)::text = ANY (ARRAY[('Maintenance'::character varying)::text, ('Examination'::character varying)::text, ('Meeting'::character varying)::text, ('Event'::character varying)::text, ('Reserved'::character varying)::text, ('Other'::character varying)::text])))
);


--
-- Name: classroom_unavailability_classroom_unavailability_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.classroom_unavailability_classroom_unavailability_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: classroom_unavailability_classroom_unavailability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.classroom_unavailability_classroom_unavailability_id_seq OWNED BY public.classroom_unavailability.classroom_unavailability_id;


--
-- Name: classrooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classrooms (
    classroom_id bigint NOT NULL,
    campus_id bigint,
    building_id bigint,
    classroom_type_id bigint NOT NULL,
    room_no character varying(30) NOT NULL,
    room_name character varying(150),
    floor_name character varying(50),
    student_capacity integer NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT classrooms_student_capacity_check CHECK ((student_capacity > 0))
);


--
-- Name: classrooms_classroom_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.classrooms_classroom_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: classrooms_classroom_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.classrooms_classroom_id_seq OWNED BY public.classrooms.classroom_id;


--
-- Name: common_master_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.common_master_types (
    master_type_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    master_type_code character varying(50) NOT NULL,
    master_type_name character varying(150) NOT NULL,
    description text,
    used_in character varying(300),
    is_system boolean DEFAULT true,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: common_master_types_master_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.common_master_types_master_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: common_master_types_master_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.common_master_types_master_type_id_seq OWNED BY public.common_master_types.master_type_id;


--
-- Name: common_master_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.common_master_values (
    master_value_id bigint NOT NULL,
    master_type_id bigint NOT NULL,
    value_code character varying(50) NOT NULL,
    value_name character varying(200) NOT NULL,
    short_name character varying(100),
    display_order integer DEFAULT 0,
    is_default boolean DEFAULT false,
    is_active boolean DEFAULT true,
    remarks text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: common_master_values_master_value_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.common_master_values_master_value_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: common_master_values_master_value_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.common_master_values_master_value_id_seq OWNED BY public.common_master_values.master_value_id;


--
-- Name: course_initial_setup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_initial_setup (
    course_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    section_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: course_offerings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_offerings (
    offering_id bigint NOT NULL,
    term_id bigint NOT NULL,
    curriculum_course_id bigint NOT NULL,
    section_id bigint NOT NULL,
    status character varying(20) DEFAULT 'PLANNED'::character varying NOT NULL
);


--
-- Name: course_offerings_offering_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.course_offerings_offering_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: course_offerings_offering_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.course_offerings_offering_id_seq OWNED BY public.course_offerings.offering_id;


--
-- Name: course_prerequisites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_prerequisites (
    course_id bigint NOT NULL,
    prerequisite_course_id bigint NOT NULL,
    CONSTRAINT course_prerequisites_check CHECK ((course_id <> prerequisite_course_id))
);


--
-- Name: course_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_results (
    course_result_id bigint NOT NULL,
    student_id bigint NOT NULL,
    offering_id bigint NOT NULL,
    internal_marks numeric(7,2),
    external_marks numeric(7,2),
    total_marks numeric(7,2),
    percentage numeric(6,2),
    grade_scale_id bigint,
    grade_point numeric(4,2),
    credit_earned numeric(5,2),
    result_status character varying(20),
    published_at timestamp with time zone
);


--
-- Name: course_results_course_result_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.course_results_course_result_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: course_results_course_result_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.course_results_course_result_id_seq OWNED BY public.course_results.course_result_id;


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    course_id bigint NOT NULL,
    department_id bigint NOT NULL,
    course_code character varying(30) NOT NULL,
    course_name character varying(200) NOT NULL,
    course_type character varying(40),
    lecture_hours numeric(4,1) DEFAULT 0,
    tutorial_hours numeric(4,1) DEFAULT 0,
    practical_hours numeric(4,1) DEFAULT 0,
    credits numeric(4,1) DEFAULT 0,
    maximum_marks numeric(6,2),
    minimum_pass_marks numeric(6,2),
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: courses_course_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.courses_course_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: courses_course_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.courses_course_id_seq OWNED BY public.courses.course_id;


--
-- Name: curriculum_courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.curriculum_courses (
    curriculum_course_id bigint NOT NULL,
    scheme_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    course_id bigint NOT NULL,
    category character varying(50),
    is_elective boolean DEFAULT false NOT NULL,
    elective_group character varying(50),
    display_order integer DEFAULT 0
);


--
-- Name: curriculum_courses_curriculum_course_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.curriculum_courses_curriculum_course_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: curriculum_courses_curriculum_course_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.curriculum_courses_curriculum_course_id_seq OWNED BY public.curriculum_courses.curriculum_course_id;


--
-- Name: curriculum_schemes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.curriculum_schemes (
    scheme_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    scheme_name character varying(100) NOT NULL,
    regulation_year smallint,
    effective_from_batch smallint,
    total_credits numeric(6,2),
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: curriculum_schemes_scheme_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.curriculum_schemes_scheme_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: curriculum_schemes_scheme_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.curriculum_schemes_scheme_id_seq OWNED BY public.curriculum_schemes.scheme_id;


--
-- Name: dashboard_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_messages (
    dashboard_message_id bigint NOT NULL,
    message_title character varying(200) NOT NULL,
    message_text text NOT NULL,
    audience_type character varying(30) DEFAULT 'All Users'::character varying NOT NULL,
    department_id bigint,
    programme_id bigint,
    display_from date NOT NULL,
    display_to date,
    priority character varying(15) DEFAULT 'Normal'::character varying NOT NULL,
    display_style character varying(20) DEFAULT 'Information'::character varying NOT NULL,
    show_on_dashboard boolean DEFAULT true NOT NULL,
    status character varying(15) DEFAULT 'Active'::character varying NOT NULL,
    display_order integer DEFAULT 1 NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT dashboard_messages_audience_type_check CHECK (((audience_type)::text = ANY (ARRAY[('All Users'::character varying)::text, ('Students'::character varying)::text, ('Faculty'::character varying)::text, ('Employees'::character varying)::text, ('Administrators'::character varying)::text, ('Department Heads'::character varying)::text, ('Specific Department'::character varying)::text, ('Specific Programme'::character varying)::text]))),
    CONSTRAINT dashboard_messages_check CHECK (((display_to IS NULL) OR (display_to >= display_from))),
    CONSTRAINT dashboard_messages_display_style_check CHECK (((display_style)::text = ANY (ARRAY[('Information'::character varying)::text, ('Success'::character varying)::text, ('Warning'::character varying)::text, ('Important'::character varying)::text]))),
    CONSTRAINT dashboard_messages_priority_check CHECK (((priority)::text = ANY (ARRAY[('Low'::character varying)::text, ('Normal'::character varying)::text, ('High'::character varying)::text, ('Urgent'::character varying)::text]))),
    CONSTRAINT dashboard_messages_status_check CHECK (((status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Expired'::character varying)::text])))
);


--
-- Name: dashboard_messages_dashboard_message_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboard_messages_dashboard_message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_messages_dashboard_message_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboard_messages_dashboard_message_id_seq OWNED BY public.dashboard_messages.dashboard_message_id;


--
-- Name: dashboard_notice_acknowledgments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_notice_acknowledgments (
    notice_acknowledgment_id bigint NOT NULL,
    notice_id bigint NOT NULL,
    user_id bigint NOT NULL,
    acknowledged_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    acknowledgment_ip character varying(50)
);


--
-- Name: dashboard_notice_acknowledgments_notice_acknowledgment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboard_notice_acknowledgments_notice_acknowledgment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_notice_acknowledgments_notice_acknowledgment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboard_notice_acknowledgments_notice_acknowledgment_id_seq OWNED BY public.dashboard_notice_acknowledgments.notice_acknowledgment_id;


--
-- Name: dashboard_notice_audiences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_notice_audiences (
    notice_audience_id bigint NOT NULL,
    notice_id bigint NOT NULL,
    audience_type character varying(30) NOT NULL,
    department_id bigint,
    programme_id bigint,
    semester_id bigint,
    role_id bigint,
    user_id bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT dashboard_notice_audiences_audience_type_check CHECK (((audience_type)::text = ANY (ARRAY[('Department'::character varying)::text, ('Programme'::character varying)::text, ('Semester'::character varying)::text, ('Role'::character varying)::text, ('User'::character varying)::text]))),
    CONSTRAINT dashboard_notice_audiences_check CHECK (((department_id IS NOT NULL) OR (programme_id IS NOT NULL) OR (semester_id IS NOT NULL) OR (role_id IS NOT NULL) OR (user_id IS NOT NULL)))
);


--
-- Name: dashboard_notice_audiences_notice_audience_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboard_notice_audiences_notice_audience_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_notice_audiences_notice_audience_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboard_notice_audiences_notice_audience_id_seq OWNED BY public.dashboard_notice_audiences.notice_audience_id;


--
-- Name: dashboard_notices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_notices (
    notice_id bigint NOT NULL,
    academic_year_id bigint,
    notice_number character varying(50) NOT NULL,
    notice_title character varying(250) NOT NULL,
    notice_category character varying(30) NOT NULL,
    notice_date date DEFAULT CURRENT_DATE NOT NULL,
    notice_description text NOT NULL,
    audience_type character varying(30) DEFAULT 'All Users'::character varying NOT NULL,
    department_id bigint,
    programme_id bigint,
    semester_id bigint,
    publish_from timestamp with time zone NOT NULL,
    publish_to timestamp with time zone,
    attachment_path character varying(500),
    external_link character varying(500),
    priority character varying(15) DEFAULT 'Normal'::character varying NOT NULL,
    is_pinned boolean DEFAULT false NOT NULL,
    requires_acknowledgment boolean DEFAULT false NOT NULL,
    send_notification boolean DEFAULT true NOT NULL,
    notice_status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    published_by bigint,
    published_at timestamp with time zone,
    created_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT dashboard_notices_audience_type_check CHECK (((audience_type)::text = ANY (ARRAY[('All Users'::character varying)::text, ('Students'::character varying)::text, ('Faculty'::character varying)::text, ('Employees'::character varying)::text, ('Administrators'::character varying)::text, ('Department Heads'::character varying)::text, ('Specific Department'::character varying)::text, ('Specific Programme'::character varying)::text, ('Specific Semester'::character varying)::text]))),
    CONSTRAINT dashboard_notices_check CHECK (((publish_to IS NULL) OR (publish_to >= publish_from))),
    CONSTRAINT dashboard_notices_notice_category_check CHECK (((notice_category)::text = ANY (ARRAY[('Academic'::character varying)::text, ('Examination'::character varying)::text, ('Administrative'::character varying)::text, ('Holiday'::character varying)::text, ('Event'::character varying)::text, ('Placement'::character varying)::text, ('Library'::character varying)::text, ('Hostel'::character varying)::text, ('Transport'::character varying)::text, ('Fees'::character varying)::text, ('General'::character varying)::text, ('Emergency'::character varying)::text]))),
    CONSTRAINT dashboard_notices_notice_status_check CHECK (((notice_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Published'::character varying)::text, ('Unpublished'::character varying)::text, ('Expired'::character varying)::text, ('Archived'::character varying)::text]))),
    CONSTRAINT dashboard_notices_priority_check CHECK (((priority)::text = ANY (ARRAY[('Low'::character varying)::text, ('Normal'::character varying)::text, ('High'::character varying)::text, ('Urgent'::character varying)::text])))
);


--
-- Name: dashboard_notices_notice_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboard_notices_notice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_notices_notice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboard_notices_notice_id_seq OWNED BY public.dashboard_notices.notice_id;


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    department_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    department_code character varying(30) NOT NULL,
    department_name character varying(150) NOT NULL,
    department_type character varying(30) DEFAULT 'ACADEMIC'::character varying,
    hod_employee_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    department_alias character varying(150),
    official_email character varying(150),
    phone character varying(20)
);


--
-- Name: departments_department_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departments_department_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departments_department_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departments_department_id_seq OWNED BY public.departments.department_id;


--
-- Name: designations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.designations (
    designation_id bigint NOT NULL,
    designation_code character varying(30) NOT NULL,
    designation_name character varying(100) NOT NULL,
    category character varying(30),
    sort_order integer DEFAULT 0,
    short_name character varying(50),
    designation_type character varying(30) DEFAULT 'TEACHING'::character varying NOT NULL,
    designation_level integer,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: designations_designation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.designations_designation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: designations_designation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.designations_designation_id_seq OWNED BY public.designations.designation_id;


--
-- Name: document_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_types (
    document_type_id bigint NOT NULL,
    document_type_code character varying(50) NOT NULL,
    document_type_name character varying(150) NOT NULL,
    applies_to character varying(30),
    is_mandatory boolean DEFAULT false NOT NULL
);


--
-- Name: document_types_document_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_types_document_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_types_document_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_types_document_type_id_seq OWNED BY public.document_types.document_type_id;


--
-- Name: employee_leaves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_leaves (
    leave_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    leave_type character varying(30) NOT NULL,
    from_date date NOT NULL,
    to_date date NOT NULL,
    reason text,
    status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL,
    approved_by bigint,
    approved_at timestamp with time zone,
    CONSTRAINT employee_leaves_check CHECK ((to_date >= from_date))
);


--
-- Name: employee_leaves_leave_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_leaves_leave_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_leaves_leave_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_leaves_leave_id_seq OWNED BY public.employee_leaves.leave_id;


--
-- Name: employee_login_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_login_history (
    history_id bigint NOT NULL,
    user_id bigint,
    employee_id bigint,
    old_login_id character varying(100),
    new_login_id character varying(100),
    changed_by bigint,
    changed_on timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    remarks text
);


--
-- Name: employee_login_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_login_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_login_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_login_history_history_id_seq OWNED BY public.employee_login_history.history_id;


--
-- Name: employee_qualifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_qualifications (
    qualification_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    degree_name character varying(150) NOT NULL,
    specialization character varying(150),
    university character varying(200),
    passing_year smallint,
    percentage_cgpa character varying(20),
    document_url text
);


--
-- Name: employee_qualifications_qualification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_qualifications_qualification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_qualifications_qualification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_qualifications_qualification_id_seq OWNED BY public.employee_qualifications.qualification_id;


--
-- Name: employees_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employees_employee_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employees_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employees_employee_id_seq OWNED BY public.employees.employee_id;


--
-- Name: exam_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_types (
    exam_type_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    exam_type_code character varying(30) NOT NULL,
    exam_type_name character varying(100) NOT NULL,
    weightage numeric(5,2)
);


--
-- Name: exam_types_exam_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exam_types_exam_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exam_types_exam_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exam_types_exam_type_id_seq OWNED BY public.exam_types.exam_type_id;


--
-- Name: examinations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.examinations (
    examination_id bigint NOT NULL,
    term_id bigint NOT NULL,
    exam_type_id bigint NOT NULL,
    examination_name character varying(150) NOT NULL,
    start_date date,
    end_date date,
    status character varying(20) DEFAULT 'PLANNED'::character varying NOT NULL
);


--
-- Name: examinations_examination_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.examinations_examination_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: examinations_examination_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.examinations_examination_id_seq OWNED BY public.examinations.examination_id;


--
-- Name: faculty_course_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.faculty_course_allocations (
    allocation_id bigint NOT NULL,
    offering_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    allocation_role character varying(30) DEFAULT 'PRIMARY'::character varying NOT NULL,
    workload_hours numeric(5,2),
    assigned_by bigint,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: faculty_course_allocations_allocation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.faculty_course_allocations_allocation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: faculty_course_allocations_allocation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.faculty_course_allocations_allocation_id_seq OWNED BY public.faculty_course_allocations.allocation_id;


--
-- Name: fee_heads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fee_heads (
    fee_head_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    fee_head_code character varying(30) NOT NULL,
    fee_head_name character varying(100) NOT NULL,
    refundable boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: fee_heads_fee_head_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fee_heads_fee_head_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fee_heads_fee_head_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fee_heads_fee_head_id_seq OWNED BY public.fee_heads.fee_head_id;


--
-- Name: fee_payment_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fee_payment_allocations (
    payment_allocation_id bigint NOT NULL,
    payment_id bigint NOT NULL,
    demand_id bigint NOT NULL,
    allocated_amount numeric(14,2) NOT NULL,
    CONSTRAINT fee_payment_allocations_allocated_amount_check CHECK ((allocated_amount > (0)::numeric))
);


--
-- Name: fee_payment_allocations_payment_allocation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fee_payment_allocations_payment_allocation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fee_payment_allocations_payment_allocation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fee_payment_allocations_payment_allocation_id_seq OWNED BY public.fee_payment_allocations.payment_allocation_id;


--
-- Name: fee_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fee_payments (
    payment_id bigint NOT NULL,
    student_id bigint NOT NULL,
    receipt_number character varying(50) NOT NULL,
    payment_date timestamp with time zone DEFAULT now() NOT NULL,
    amount numeric(14,2) NOT NULL,
    payment_mode character varying(30) NOT NULL,
    transaction_reference character varying(150),
    bank_name character varying(100),
    payment_status character varying(20) DEFAULT 'SUCCESS'::character varying NOT NULL,
    received_by bigint,
    remarks text,
    CONSTRAINT fee_payments_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: fee_payments_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fee_payments_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fee_payments_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fee_payments_payment_id_seq OWNED BY public.fee_payments.payment_id;


--
-- Name: fee_structure_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fee_structure_items (
    fee_structure_item_id bigint NOT NULL,
    fee_structure_id bigint NOT NULL,
    fee_head_id bigint NOT NULL,
    semester_id bigint,
    amount numeric(14,2) NOT NULL,
    due_date date,
    CONSTRAINT fee_structure_items_amount_check CHECK ((amount >= (0)::numeric))
);


--
-- Name: fee_structure_items_fee_structure_item_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fee_structure_items_fee_structure_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fee_structure_items_fee_structure_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fee_structure_items_fee_structure_item_id_seq OWNED BY public.fee_structure_items.fee_structure_item_id;


--
-- Name: fee_structures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fee_structures (
    fee_structure_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    batch_id bigint,
    academic_year_id bigint NOT NULL,
    category character varying(30) DEFAULT 'GENERAL'::character varying,
    structure_name character varying(150) NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: fee_structures_fee_structure_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fee_structures_fee_structure_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fee_structures_fee_structure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fee_structures_fee_structure_id_seq OWNED BY public.fee_structures.fee_structure_id;


--
-- Name: file_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.file_attachments (
    attachment_id bigint NOT NULL,
    entity_type character varying(80) NOT NULL,
    entity_id bigint NOT NULL,
    original_file_name character varying(255) NOT NULL,
    stored_file_name character varying(255),
    file_url text NOT NULL,
    mime_type character varying(100),
    file_size_bytes bigint,
    uploaded_by bigint,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: file_attachments_attachment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.file_attachments_attachment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_attachments_attachment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.file_attachments_attachment_id_seq OWNED BY public.file_attachments.attachment_id;


--
-- Name: grade_scales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grade_scales (
    grade_scale_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    grade_letter character varying(5) NOT NULL,
    minimum_percentage numeric(5,2) NOT NULL,
    maximum_percentage numeric(5,2) NOT NULL,
    grade_point numeric(4,2) NOT NULL,
    description character varying(100)
);


--
-- Name: grade_scales_grade_scale_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.grade_scales_grade_scale_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: grade_scales_grade_scale_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.grade_scales_grade_scale_id_seq OWNED BY public.grade_scales.grade_scale_id;


--
-- Name: grievance_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grievance_actions (
    grievance_action_id bigint NOT NULL,
    grievance_id bigint NOT NULL,
    action_by bigint NOT NULL,
    action_note text NOT NULL,
    old_status character varying(20),
    new_status character varying(20),
    action_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: grievance_actions_grievance_action_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.grievance_actions_grievance_action_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: grievance_actions_grievance_action_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.grievance_actions_grievance_action_id_seq OWNED BY public.grievance_actions.grievance_action_id;


--
-- Name: grievances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grievances (
    grievance_id bigint NOT NULL,
    submitted_by bigint NOT NULL,
    grievance_category character varying(50) NOT NULL,
    subject character varying(250) NOT NULL,
    description text NOT NULL,
    priority character varying(20) DEFAULT 'MEDIUM'::character varying NOT NULL,
    assigned_to bigint,
    status character varying(20) DEFAULT 'OPEN'::character varying NOT NULL,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone
);


--
-- Name: grievances_grievance_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.grievances_grievance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: grievances_grievance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.grievances_grievance_id_seq OWNED BY public.grievances.grievance_id;


--
-- Name: guardians; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.guardians (
    guardian_id bigint NOT NULL,
    guardian_name character varying(150) NOT NULL,
    relationship character varying(30) NOT NULL,
    occupation character varying(100),
    annual_income numeric(14,2),
    mobile character varying(20),
    alternate_mobile character varying(20),
    email character varying(150),
    address text
);


--
-- Name: guardians_guardian_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.guardians_guardian_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: guardians_guardian_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.guardians_guardian_id_seq OWNED BY public.guardians.guardian_id;


--
-- Name: hostel_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hostel_allocations (
    hostel_allocation_id bigint NOT NULL,
    student_id bigint NOT NULL,
    hostel_room_id bigint NOT NULL,
    bed_number character varying(20),
    allocated_from date NOT NULL,
    allocated_to date,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL
);


--
-- Name: hostel_allocations_hostel_allocation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hostel_allocations_hostel_allocation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hostel_allocations_hostel_allocation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hostel_allocations_hostel_allocation_id_seq OWNED BY public.hostel_allocations.hostel_allocation_id;


--
-- Name: hostel_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hostel_rooms (
    hostel_room_id bigint NOT NULL,
    hostel_id bigint NOT NULL,
    room_number character varying(30) NOT NULL,
    room_type character varying(30),
    capacity smallint NOT NULL,
    monthly_charge numeric(12,2)
);


--
-- Name: hostel_rooms_hostel_room_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hostel_rooms_hostel_room_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hostel_rooms_hostel_room_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hostel_rooms_hostel_room_id_seq OWNED BY public.hostel_rooms.hostel_room_id;


--
-- Name: hostels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hostels (
    hostel_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    hostel_name character varying(100) NOT NULL,
    hostel_type character varying(20),
    warden_employee_id bigint,
    capacity integer,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: hostels_hostel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hostels_hostel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hostels_hostel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hostels_hostel_id_seq OWNED BY public.hostels.hostel_id;


--
-- Name: institutions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.institutions (
    institution_id bigint NOT NULL,
    institution_code character varying(30) NOT NULL,
    institution_name character varying(200) NOT NULL,
    address_line1 character varying(200),
    address_line2 character varying(200),
    city character varying(100),
    district character varying(100),
    state character varying(100),
    postal_code character varying(10),
    phone character varying(20),
    email character varying(150),
    website character varying(200),
    logo_url text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: institutions_institution_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.institutions_institution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: institutions_institution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.institutions_institution_id_seq OWNED BY public.institutions.institution_id;


--
-- Name: issue_followups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_followups (
    followup_id bigint NOT NULL,
    student_issue_id bigint NOT NULL,
    followup_date date NOT NULL,
    remarks text NOT NULL,
    next_action text,
    next_followup_date date,
    updated_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: issue_followups_followup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.issue_followups_followup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issue_followups_followup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.issue_followups_followup_id_seq OWNED BY public.issue_followups.followup_id;


--
-- Name: libraries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.libraries (
    library_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    campus_id bigint,
    library_code character varying(30) NOT NULL,
    library_name character varying(150) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: libraries_library_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.libraries_library_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: libraries_library_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.libraries_library_id_seq OWNED BY public.libraries.library_id;


--
-- Name: library_almiras; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_almiras (
    almira_id bigint NOT NULL,
    library_id bigint NOT NULL,
    room_id bigint,
    almira_code character varying(30) NOT NULL,
    almira_name character varying(120) NOT NULL,
    number_of_shelves integer NOT NULL,
    capacity integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT library_almiras_capacity_check CHECK ((capacity > 0)),
    CONSTRAINT library_almiras_number_of_shelves_check CHECK ((number_of_shelves > 0))
);


--
-- Name: library_almiras_almira_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_almiras_almira_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_almiras_almira_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_almiras_almira_id_seq OWNED BY public.library_almiras.almira_id;


--
-- Name: library_authors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_authors (
    author_id bigint NOT NULL,
    author_name character varying(200) NOT NULL,
    alias character varying(120),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    author_code character varying(30)
);


--
-- Name: library_authors_author_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_authors_author_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_authors_author_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_authors_author_id_seq OWNED BY public.library_authors.author_id;


--
-- Name: library_book_copies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_book_copies (
    book_copy_id bigint NOT NULL,
    book_id bigint NOT NULL,
    accession_number character varying(50) NOT NULL,
    barcode character varying(100),
    purchase_date date,
    price numeric(12,2),
    copy_status character varying(30) DEFAULT 'AVAILABLE'::character varying NOT NULL
);


--
-- Name: library_book_copies_book_copy_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_book_copies_book_copy_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_book_copies_book_copy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_book_copies_book_copy_id_seq OWNED BY public.library_book_copies.book_copy_id;


--
-- Name: library_book_issues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_book_issues (
    book_issue_id bigint NOT NULL,
    book_copy_id bigint NOT NULL,
    issue_type_id bigint NOT NULL,
    member_code character varying(50) NOT NULL,
    member_name character varying(200) NOT NULL,
    member_type character varying(30) NOT NULL,
    department_id bigint,
    contact_number character varying(30),
    issue_date date NOT NULL,
    due_date date NOT NULL,
    returned_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    issue_number character varying(40) NOT NULL,
    designation character varying(150),
    programme character varying(150),
    semester character varying(50),
    issue_remarks text,
    fine_amount numeric(12,2) DEFAULT 0 NOT NULL,
    book_condition character varying(30),
    return_remarks text
);


--
-- Name: library_book_issues_book_issue_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_book_issues_book_issue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_book_issues_book_issue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_book_issues_book_issue_id_seq OWNED BY public.library_book_issues.book_issue_id;


--
-- Name: library_book_stock; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_book_stock (
    book_id bigint NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT library_book_stock_quantity_check CHECK ((quantity >= 0))
);


--
-- Name: library_books; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_books (
    book_id bigint NOT NULL,
    isbn character varying(30),
    title character varying(300) NOT NULL,
    author character varying(250),
    publisher character varying(200),
    edition character varying(50),
    publication_year smallint,
    subject character varying(150),
    category character varying(100),
    language character varying(50),
    shelf_location character varying(50),
    title_id bigint,
    author_id bigint,
    publisher_id bigint,
    category_id bigint,
    subject_id bigint,
    pages integer,
    book_type character varying(50) DEFAULT 'Text Book'::character varying NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: library_books_book_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_books_book_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_books_book_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_books_book_id_seq OWNED BY public.library_books.book_id;


--
-- Name: library_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_categories (
    category_id bigint NOT NULL,
    category_code character varying(30) NOT NULL,
    category_name character varying(200) NOT NULL,
    parent_category_id bigint,
    issue_allowed boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: library_categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_categories_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_categories_category_id_seq OWNED BY public.library_categories.category_id;


--
-- Name: library_issue_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_issue_types (
    issue_type_id bigint NOT NULL,
    issue_type_code character varying(30) NOT NULL,
    issue_type_name character varying(150) NOT NULL,
    member_type character varying(30) NOT NULL,
    maximum_books integer NOT NULL,
    issue_duration_days integer NOT NULL,
    fine_per_day numeric(10,2) DEFAULT 0 NOT NULL,
    renewal_allowed boolean DEFAULT true NOT NULL,
    maximum_renewals integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT library_issue_types_fine_per_day_check CHECK ((fine_per_day >= (0)::numeric)),
    CONSTRAINT library_issue_types_issue_duration_days_check CHECK ((issue_duration_days > 0)),
    CONSTRAINT library_issue_types_maximum_books_check CHECK ((maximum_books > 0)),
    CONSTRAINT library_issue_types_maximum_renewals_check CHECK ((maximum_renewals >= 0))
);


--
-- Name: library_issue_types_issue_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_issue_types_issue_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_issue_types_issue_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_issue_types_issue_type_id_seq OWNED BY public.library_issue_types.issue_type_id;


--
-- Name: library_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_members (
    library_member_id bigint NOT NULL,
    user_id bigint NOT NULL,
    membership_number character varying(50) NOT NULL,
    member_type character varying(30) NOT NULL,
    joined_on date DEFAULT CURRENT_DATE NOT NULL,
    valid_until date,
    max_books_allowed smallint DEFAULT 3,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: library_members_library_member_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_members_library_member_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_members_library_member_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_members_library_member_id_seq OWNED BY public.library_members.library_member_id;


--
-- Name: library_publishers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_publishers (
    publisher_id bigint NOT NULL,
    publisher_code character varying(30) NOT NULL,
    publisher_name character varying(250) NOT NULL,
    contact_person character varying(150),
    phone character varying(30),
    email character varying(150),
    website character varying(250),
    address text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: library_publishers_publisher_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_publishers_publisher_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_publishers_publisher_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_publishers_publisher_id_seq OWNED BY public.library_publishers.publisher_id;


--
-- Name: library_purchase_invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_purchase_invoice_items (
    invoice_item_id bigint NOT NULL,
    invoice_id bigint NOT NULL,
    book_id bigint NOT NULL,
    ordered_quantity integer NOT NULL,
    received_quantity integer NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    line_total numeric(14,2) NOT NULL,
    CONSTRAINT library_purchase_invoice_items_line_total_check CHECK ((line_total >= (0)::numeric)),
    CONSTRAINT library_purchase_invoice_items_ordered_quantity_check CHECK ((ordered_quantity >= 0)),
    CONSTRAINT library_purchase_invoice_items_received_quantity_check CHECK ((received_quantity > 0)),
    CONSTRAINT library_purchase_invoice_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: library_purchase_invoice_items_invoice_item_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_purchase_invoice_items_invoice_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_purchase_invoice_items_invoice_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_purchase_invoice_items_invoice_item_id_seq OWNED BY public.library_purchase_invoice_items.invoice_item_id;


--
-- Name: library_purchase_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_purchase_invoices (
    invoice_id bigint NOT NULL,
    invoice_number character varying(50) NOT NULL,
    invoice_date date NOT NULL,
    supplier_id bigint NOT NULL,
    purchase_order_id bigint,
    payment_status character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    invoice_file_name character varying(250),
    stock_status character varying(20) DEFAULT 'DRAFT'::character varying NOT NULL,
    invoice_total numeric(14,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    posted_at timestamp with time zone,
    posted_by bigint
);


--
-- Name: library_purchase_invoices_invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_purchase_invoices_invoice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_purchase_invoices_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_purchase_invoices_invoice_id_seq OWNED BY public.library_purchase_invoices.invoice_id;


--
-- Name: library_purchase_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_purchase_order_items (
    purchase_order_item_id bigint NOT NULL,
    purchase_order_id bigint NOT NULL,
    item_type character varying(30) NOT NULL,
    book_id bigint,
    item_name character varying(250) NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    discount numeric(12,2) DEFAULT 0 NOT NULL,
    tax numeric(12,2) DEFAULT 0 NOT NULL,
    line_total numeric(14,2) NOT NULL,
    CONSTRAINT library_purchase_order_items_discount_check CHECK ((discount >= (0)::numeric)),
    CONSTRAINT library_purchase_order_items_line_total_check CHECK ((line_total >= (0)::numeric)),
    CONSTRAINT library_purchase_order_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT library_purchase_order_items_tax_check CHECK ((tax >= (0)::numeric)),
    CONSTRAINT library_purchase_order_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: library_purchase_order_items_purchase_order_item_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_purchase_order_items_purchase_order_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_purchase_order_items_purchase_order_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_purchase_order_items_purchase_order_item_id_seq OWNED BY public.library_purchase_order_items.purchase_order_item_id;


--
-- Name: library_purchase_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_purchase_orders (
    purchase_order_id bigint NOT NULL,
    po_number character varying(40) NOT NULL,
    supplier_id bigint NOT NULL,
    order_date date DEFAULT CURRENT_DATE NOT NULL,
    status character varying(30) DEFAULT 'DRAFT'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    expected_delivery date,
    delivery_address text,
    terms_conditions text,
    subtotal numeric(14,2) DEFAULT 0 NOT NULL,
    discount_total numeric(14,2) DEFAULT 0 NOT NULL,
    tax_total numeric(14,2) DEFAULT 0 NOT NULL,
    grand_total numeric(14,2) DEFAULT 0 NOT NULL,
    approved_at timestamp with time zone,
    approved_by bigint
);


--
-- Name: library_purchase_orders_purchase_order_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_purchase_orders_purchase_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_purchase_orders_purchase_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_purchase_orders_purchase_order_id_seq OWNED BY public.library_purchase_orders.purchase_order_id;


--
-- Name: library_student_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_student_members (
    student_member_id bigint NOT NULL,
    roll_number character varying(50) NOT NULL,
    student_name character varying(200) NOT NULL,
    programme character varying(150) NOT NULL,
    department_id bigint,
    semester character varying(50),
    contact_number character varying(30),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: library_student_members_student_member_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_student_members_student_member_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_student_members_student_member_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_student_members_student_member_id_seq OWNED BY public.library_student_members.student_member_id;


--
-- Name: library_study_material_issues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_study_material_issues (
    material_issue_id bigint NOT NULL,
    study_material_id bigint NOT NULL,
    department_id bigint,
    recipient_code character varying(50) NOT NULL,
    recipient_name character varying(200) NOT NULL,
    recipient_type character varying(30) NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12,2) DEFAULT 0 NOT NULL,
    amount numeric(14,2) DEFAULT 0 NOT NULL,
    issued_date date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    issue_number character varying(40) NOT NULL,
    programme character varying(150),
    payment_status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL,
    remarks text,
    CONSTRAINT library_study_material_issues_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT library_study_material_issues_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT library_study_material_issues_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: library_study_material_issues_material_issue_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_study_material_issues_material_issue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_study_material_issues_material_issue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_study_material_issues_material_issue_id_seq OWNED BY public.library_study_material_issues.material_issue_id;


--
-- Name: library_study_material_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_study_material_prices (
    price_id bigint NOT NULL,
    study_material_id bigint NOT NULL,
    effective_from date NOT NULL,
    purchase_price numeric(12,2) NOT NULL,
    selling_price numeric(12,2) NOT NULL,
    student_price numeric(12,2) NOT NULL,
    staff_price numeric(12,2) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT library_study_material_prices_purchase_price_check CHECK ((purchase_price >= (0)::numeric)),
    CONSTRAINT library_study_material_prices_selling_price_check CHECK ((selling_price >= (0)::numeric)),
    CONSTRAINT library_study_material_prices_staff_price_check CHECK ((staff_price >= (0)::numeric)),
    CONSTRAINT library_study_material_prices_student_price_check CHECK ((student_price >= (0)::numeric))
);


--
-- Name: library_study_material_prices_price_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_study_material_prices_price_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_study_material_prices_price_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_study_material_prices_price_id_seq OWNED BY public.library_study_material_prices.price_id;


--
-- Name: library_study_materials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_study_materials (
    study_material_id bigint NOT NULL,
    material_code character varying(30) NOT NULL,
    material_name character varying(200) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    material_type character varying(50) DEFAULT 'OTHER'::character varying NOT NULL,
    subject_id bigint,
    academic_year_id bigint,
    current_stock integer DEFAULT 0 NOT NULL,
    minimum_stock integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: library_study_materials_study_material_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_study_materials_study_material_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_study_materials_study_material_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_study_materials_study_material_id_seq OWNED BY public.library_study_materials.study_material_id;


--
-- Name: library_subjects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_subjects (
    subject_id bigint NOT NULL,
    subject_code character varying(30) NOT NULL,
    subject_name character varying(200) NOT NULL,
    subject_alias character varying(120),
    department_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: library_subjects_subject_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_subjects_subject_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_subjects_subject_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_subjects_subject_id_seq OWNED BY public.library_subjects.subject_id;


--
-- Name: library_suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_suppliers (
    supplier_id bigint NOT NULL,
    supplier_code character varying(30) NOT NULL,
    supplier_name character varying(200) NOT NULL,
    contact_person character varying(150),
    phone character varying(30),
    email character varying(150),
    gst_number character varying(30),
    pan_number character varying(20),
    address text,
    payment_terms character varying(250),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: library_suppliers_supplier_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_suppliers_supplier_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_suppliers_supplier_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_suppliers_supplier_id_seq OWNED BY public.library_suppliers.supplier_id;


--
-- Name: library_titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_titles (
    title_id bigint NOT NULL,
    title_code character varying(30),
    title_name character varying(250) NOT NULL,
    short_name character varying(120),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    subtitle character varying(250),
    language character varying(80),
    description text
);


--
-- Name: library_titles_title_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_titles_title_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_titles_title_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_titles_title_id_seq OWNED BY public.library_titles.title_id;


--
-- Name: library_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_transactions (
    library_transaction_id bigint NOT NULL,
    book_copy_id bigint NOT NULL,
    library_member_id bigint NOT NULL,
    issue_date date NOT NULL,
    due_date date NOT NULL,
    return_date date,
    fine_amount numeric(10,2) DEFAULT 0 NOT NULL,
    fine_paid boolean DEFAULT false NOT NULL,
    issued_by bigint,
    received_by bigint
);


--
-- Name: library_transactions_library_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.library_transactions_library_transaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: library_transactions_library_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.library_transactions_library_transaction_id_seq OWNED BY public.library_transactions.library_transaction_id;


--
-- Name: login_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_history (
    login_history_id bigint NOT NULL,
    user_id bigint,
    username character varying(150) NOT NULL,
    login_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    logout_at timestamp with time zone,
    ip_address inet,
    user_agent text,
    browser_name character varying(100),
    operating_system character varying(100),
    device_type character varying(50),
    session_token_hash character varying(255),
    login_status character varying(30) DEFAULT 'Active'::character varying NOT NULL,
    login_success boolean DEFAULT true NOT NULL,
    failure_reason character varying(250),
    last_activity_at timestamp with time zone,
    logout_type character varying(30),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT login_history_login_status_check CHECK (((login_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Logged Out'::character varying)::text, ('Session Expired'::character varying)::text, ('Failed Login'::character varying)::text, ('Locked'::character varying)::text, ('Terminated'::character varying)::text]))),
    CONSTRAINT login_history_logout_type_check CHECK (((logout_type IS NULL) OR ((logout_type)::text = ANY (ARRAY[('Manual'::character varying)::text, ('Automatic'::character varying)::text, ('Session Expired'::character varying)::text, ('Administrator'::character varying)::text, ('System'::character varying)::text]))))
);


--
-- Name: login_history_login_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.login_history_login_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: login_history_login_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.login_history_login_history_id_seq OWNED BY public.login_history.login_history_id;


--
-- Name: login_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_logs (
    login_log_id bigint NOT NULL,
    user_id bigint,
    username_attempted character varying(80),
    login_at timestamp with time zone DEFAULT now() NOT NULL,
    logout_at timestamp with time zone,
    login_status character varying(20) NOT NULL,
    ip_address inet,
    user_agent text
);


--
-- Name: login_logs_login_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.login_logs_login_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: login_logs_login_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.login_logs_login_log_id_seq OWNED BY public.login_logs.login_log_id;


--
-- Name: mentor_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mentor_assignments (
    mentor_assignment_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    student_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    assigned_from date DEFAULT CURRENT_DATE NOT NULL,
    assigned_to date,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: mentor_assignments_mentor_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mentor_assignments_mentor_assignment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentor_assignments_mentor_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mentor_assignments_mentor_assignment_id_seq OWNED BY public.mentor_assignments.mentor_assignment_id;


--
-- Name: mentor_meetings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mentor_meetings (
    mentor_meeting_id bigint NOT NULL,
    mentor_assignment_id bigint NOT NULL,
    meeting_date date NOT NULL,
    meeting_type character varying(30) DEFAULT 'INDIVIDUAL'::character varying,
    agenda text,
    discussion_summary text,
    action_items text,
    next_follow_up_date date,
    student_present boolean DEFAULT true NOT NULL,
    created_by bigint
);


--
-- Name: mentor_meetings_mentor_meeting_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mentor_meetings_mentor_meeting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentor_meetings_mentor_meeting_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mentor_meetings_mentor_meeting_id_seq OWNED BY public.mentor_meetings.mentor_meeting_id;


--
-- Name: mentoring_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mentoring_topics (
    mentoring_topic_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    topic_code character varying(30) NOT NULL,
    topic_name character varying(120) NOT NULL,
    description text,
    display_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint
);


--
-- Name: mentoring_topics_mentoring_topic_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mentoring_topics_mentoring_topic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mentoring_topics_mentoring_topic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mentoring_topics_mentoring_topic_id_seq OWNED BY public.mentoring_topics.mentoring_topic_id;


--
-- Name: notices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notices (
    notice_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    title character varying(250) NOT NULL,
    notice_body text NOT NULL,
    audience_type character varying(30) NOT NULL,
    department_id bigint,
    publish_from timestamp with time zone DEFAULT now() NOT NULL,
    publish_until timestamp with time zone,
    attachment_url text,
    published_by bigint,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: notices_notice_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notices_notice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notices_notice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notices_notice_id_seq OWNED BY public.notices.notice_id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    notification_id bigint NOT NULL,
    user_id bigint NOT NULL,
    title character varying(200) NOT NULL,
    message text NOT NULL,
    notification_type character varying(30),
    reference_type character varying(50),
    reference_id bigint,
    is_read boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    read_at timestamp with time zone
);


--
-- Name: notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_notification_id_seq OWNED BY public.notifications.notification_id;


--
-- Name: password_reset_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_history (
    reset_id bigint NOT NULL,
    user_id bigint,
    reset_by bigint,
    reset_on timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    temporary_password boolean DEFAULT true,
    remarks text
);


--
-- Name: password_reset_history_reset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.password_reset_history_reset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: password_reset_history_reset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.password_reset_history_reset_id_seq OWNED BY public.password_reset_history.reset_id;


--
-- Name: permission_change_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permission_change_history (
    history_id bigint NOT NULL,
    user_id bigint,
    role_id bigint,
    menu_id bigint,
    permission_id bigint,
    old_value boolean,
    new_value boolean,
    action_type character varying(30) NOT NULL,
    changed_by bigint,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    remarks character varying(500),
    CONSTRAINT permission_change_history_action_type_check CHECK (((action_type)::text = ANY ((ARRAY['GRANT'::character varying, 'REVOKE'::character varying, 'ROLE_ASSIGN'::character varying, 'ROLE_REMOVE'::character varying])::text[])))
);


--
-- Name: permission_change_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.permission_change_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permission_change_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.permission_change_history_history_id_seq OWNED BY public.permission_change_history.history_id;


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    permission_id bigint NOT NULL,
    module_name character varying(80) NOT NULL,
    permission_code character varying(120) NOT NULL,
    permission_name character varying(150) NOT NULL,
    description text
);


--
-- Name: permissions_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.permissions_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.permissions_permission_id_seq OWNED BY public.permissions.permission_id;


--
-- Name: preferred_books; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.preferred_books (
    preferred_book_id bigint NOT NULL,
    subject_master_id bigint NOT NULL,
    book_title character varying(250) NOT NULL,
    author_name character varying(200) NOT NULL,
    publisher_name character varying(200),
    edition character varying(50),
    isbn character varying(30),
    book_type character varying(30) DEFAULT 'TEXT_BOOK'::character varying NOT NULL,
    display_order integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT preferred_books_display_order_check CHECK ((display_order > 0))
);


--
-- Name: preferred_books_preferred_book_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.preferred_books_preferred_book_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: preferred_books_preferred_book_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.preferred_books_preferred_book_id_seq OWNED BY public.preferred_books.preferred_book_id;


--
-- Name: programme_section_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.programme_section_merges (
    merge_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    target_section_id bigint,
    source_sections text NOT NULL,
    target_section_name character varying(100) NOT NULL,
    total_students integer DEFAULT 0 NOT NULL,
    target_capacity integer NOT NULL,
    effective_date date NOT NULL,
    merge_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint
);


--
-- Name: programme_section_merges_merge_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.programme_section_merges_merge_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: programme_section_merges_merge_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.programme_section_merges_merge_id_seq OWNED BY public.programme_section_merges.merge_id;


--
-- Name: programme_semester_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.programme_semester_definitions (
    programme_semester_id bigint NOT NULL,
    course_id bigint NOT NULL,
    programme_batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    class_type character varying(20) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    consider_for_accounting boolean DEFAULT false NOT NULL,
    created_by bigint,
    updated_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT programme_semester_definitions_class_type_check CHECK (((class_type)::text = ANY ((ARRAY['SECTION'::character varying, 'HOUSE'::character varying])::text[])))
);


--
-- Name: programme_semester_definitions_programme_semester_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.programme_semester_definitions_programme_semester_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: programme_semester_definitions_programme_semester_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.programme_semester_definitions_programme_semester_id_seq OWNED BY public.programme_semester_definitions.programme_semester_id;


--
-- Name: programmes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.programmes (
    programme_id bigint NOT NULL,
    department_id bigint NOT NULL,
    programme_code character varying(30) NOT NULL,
    programme_name character varying(150) NOT NULL,
    programme_level character varying(30),
    duration_years numeric(3,1) NOT NULL,
    total_semesters smallint NOT NULL,
    intake_capacity integer,
    regulatory_body character varying(100),
    is_active boolean DEFAULT true NOT NULL,
    programme_alias character varying(100),
    programme_type character varying(40) DEFAULT 'UNDERGRADUATE'::character varying NOT NULL,
    award_type character varying(40) DEFAULT 'DEGREE'::character varying NOT NULL,
    affiliating_university character varying(200),
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL
);


--
-- Name: programmes_programme_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.programmes_programme_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: programmes_programme_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.programmes_programme_id_seq OWNED BY public.programmes.programme_id;


--
-- Name: prospective_student_followups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prospective_student_followups (
    prospective_student_followup_id bigint NOT NULL,
    prospective_student_mentor_allotment_id bigint NOT NULL,
    followup_date date DEFAULT CURRENT_DATE NOT NULL,
    followup_mode character varying(20),
    discussion_notes text,
    candidate_response text,
    next_followup_date date,
    followup_status character varying(30) DEFAULT 'Interested'::character varying NOT NULL,
    followed_up_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT prospective_student_followups_followup_mode_check CHECK (((followup_mode)::text = ANY (ARRAY[('Call'::character varying)::text, ('SMS'::character varying)::text, ('Email'::character varying)::text, ('Online'::character varying)::text, ('Campus Visit'::character varying)::text]))),
    CONSTRAINT prospective_student_followups_followup_status_check CHECK (((followup_status)::text = ANY (ARRAY[('Interested'::character varying)::text, ('Not Interested'::character varying)::text, ('Call Later'::character varying)::text, ('Applied'::character varying)::text, ('Admitted'::character varying)::text, ('No Response'::character varying)::text])))
);


--
-- Name: prospective_student_followups_prospective_student_followup__seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prospective_student_followups_prospective_student_followup__seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prospective_student_followups_prospective_student_followup__seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prospective_student_followups_prospective_student_followup__seq OWNED BY public.prospective_student_followups.prospective_student_followup_id;


--
-- Name: prospective_student_mentor_allotments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prospective_student_mentor_allotments (
    prospective_student_mentor_allotment_id bigint NOT NULL,
    prospective_student_id bigint NOT NULL,
    mentor_employee_id bigint NOT NULL,
    allotment_date date DEFAULT CURRENT_DATE NOT NULL,
    next_follow_up_date date,
    allotment_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    remarks text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT prospective_student_mentor_allotments_allotment_status_check CHECK (((allotment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Converted'::character varying)::text, ('Closed'::character varying)::text, ('Cancelled'::character varying)::text])))
);


--
-- Name: prospective_student_mentor_al_prospective_student_mentor_al_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prospective_student_mentor_al_prospective_student_mentor_al_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prospective_student_mentor_al_prospective_student_mentor_al_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prospective_student_mentor_al_prospective_student_mentor_al_seq OWNED BY public.prospective_student_mentor_allotments.prospective_student_mentor_allotment_id;


--
-- Name: prospective_students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prospective_students (
    prospective_student_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    academic_year_id bigint,
    enquiry_number character varying(40) NOT NULL,
    applicant_name character varying(180) NOT NULL,
    mobile_number character varying(20),
    email character varying(150),
    department_id bigint,
    programme_id bigint,
    admission_status_value_id bigint,
    enquiry_date date DEFAULT CURRENT_DATE NOT NULL,
    source_of_enquiry character varying(100),
    is_converted boolean DEFAULT false NOT NULL,
    converted_student_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: prospective_students_prospective_student_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prospective_students_prospective_student_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prospective_students_prospective_student_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prospective_students_prospective_student_id_seq OWNED BY public.prospective_students.prospective_student_id;


--
-- Name: reviewer_allotment_mentors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviewer_allotment_mentors (
    student_reviewer_allotment_id bigint NOT NULL,
    mentor_employee_id bigint NOT NULL
);


--
-- Name: reviewer_allotment_students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviewer_allotment_students (
    student_reviewer_allotment_id bigint NOT NULL,
    student_id bigint NOT NULL
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    can_view boolean DEFAULT true NOT NULL,
    can_create boolean DEFAULT false NOT NULL,
    can_update boolean DEFAULT false NOT NULL,
    can_delete boolean DEFAULT false NOT NULL,
    can_approve boolean DEFAULT false NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    role_id bigint NOT NULL,
    role_code character varying(50) NOT NULL,
    role_name character varying(100) NOT NULL,
    description text,
    hierarchy_level integer DEFAULT 100 NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: roles_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_role_id_seq OWNED BY public.roles.role_id;


--
-- Name: rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rooms (
    room_id bigint NOT NULL,
    building_id bigint,
    room_number character varying(30) NOT NULL,
    room_name character varying(100),
    room_type character varying(30) DEFAULT 'CLASSROOM'::character varying,
    capacity integer,
    is_active boolean DEFAULT true NOT NULL,
    floor_level character varying(40),
    description text,
    facilities jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: rooms_room_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rooms_room_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rooms_room_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rooms_room_id_seq OWNED BY public.rooms.room_id;


--
-- Name: route_vehicle_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.route_vehicle_assignments (
    assignment_id bigint NOT NULL,
    route_id bigint NOT NULL,
    vehicle_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    valid_from date,
    valid_to date
);


--
-- Name: route_vehicle_assignments_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.route_vehicle_assignments_assignment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: route_vehicle_assignments_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.route_vehicle_assignments_assignment_id_seq OWNED BY public.route_vehicle_assignments.assignment_id;


--
-- Name: scholarships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scholarships (
    scholarship_id bigint NOT NULL,
    scholarship_name character varying(150) NOT NULL,
    provider_name character varying(150),
    scholarship_type character varying(50),
    description text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: scholarships_scholarship_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.scholarships_scholarship_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scholarships_scholarship_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.scholarships_scholarship_id_seq OWNED BY public.scholarships.scholarship_id;


--
-- Name: section_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.section_definitions (
    section_definition_id bigint NOT NULL,
    section_name character varying(100) NOT NULL,
    section_master_id bigint NOT NULL,
    admission_course_id bigint NOT NULL,
    course_id bigint NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


--
-- Name: section_definitions_section_definition_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.section_definitions_section_definition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: section_definitions_section_definition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.section_definitions_section_definition_id_seq OWNED BY public.section_definitions.section_definition_id;


--
-- Name: section_masters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.section_masters (
    section_master_id bigint NOT NULL,
    section_master_code character varying(30) NOT NULL,
    section_master_name character varying(100) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: section_masters_section_master_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.section_masters_section_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: section_masters_section_master_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.section_masters_section_master_id_seq OWNED BY public.section_masters.section_master_id;


--
-- Name: section_merge_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.section_merge_groups (
    merge_group_id bigint NOT NULL,
    first_section_id bigint NOT NULL,
    second_section_id bigint NOT NULL,
    merged_section_name character varying(150) NOT NULL,
    total_students integer DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT section_merge_groups_check CHECK ((first_section_id <> second_section_id)),
    CONSTRAINT section_merge_groups_status_check CHECK (((status)::text = ANY (ARRAY[('ACTIVE'::character varying)::text, ('INACTIVE'::character varying)::text])))
);


--
-- Name: section_merge_groups_merge_group_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.section_merge_groups_merge_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: section_merge_groups_merge_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.section_merge_groups_merge_group_id_seq OWNED BY public.section_merge_groups.merge_group_id;


--
-- Name: sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sections (
    section_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    term_id bigint NOT NULL,
    section_name character varying(100) NOT NULL,
    strength_limit integer,
    class_coordinator_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    section_master_id bigint
);


--
-- Name: sections_section_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sections_section_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sections_section_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sections_section_id_seq OWNED BY public.sections.section_id;


--
-- Name: semester_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semester_results (
    semester_result_id bigint NOT NULL,
    student_id bigint NOT NULL,
    term_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    registered_credits numeric(6,2),
    earned_credits numeric(6,2),
    sgpa numeric(4,2),
    cgpa numeric(4,2),
    result_status character varying(20),
    published_at timestamp with time zone
);


--
-- Name: semester_results_semester_result_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.semester_results_semester_result_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: semester_results_semester_result_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.semester_results_semester_result_id_seq OWNED BY public.semester_results.semester_result_id;


--
-- Name: semesters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semesters (
    semester_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    semester_number smallint NOT NULL,
    semester_name character varying(50) NOT NULL,
    year_number smallint,
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT semesters_semester_number_check CHECK ((semester_number > 0))
);


--
-- Name: semesters_semester_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.semesters_semester_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: semesters_semester_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.semesters_semester_id_seq OWNED BY public.semesters.semester_id;


--
-- Name: student_academic_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_academic_history (
    history_id bigint NOT NULL,
    student_id bigint NOT NULL,
    qualification character varying(100) NOT NULL,
    institution_name character varying(200),
    board_university character varying(200),
    passing_year smallint,
    marks_obtained numeric(10,2),
    maximum_marks numeric(10,2),
    percentage_cgpa character varying(20),
    document_url text
);


--
-- Name: student_academic_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_academic_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_academic_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_academic_history_history_id_seq OWNED BY public.student_academic_history.history_id;


--
-- Name: student_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_addresses (
    student_address_id bigint NOT NULL,
    student_id bigint NOT NULL,
    address_type character varying(20) NOT NULL,
    address_line1 character varying(250),
    address_line2 character varying(250),
    village_town character varying(120),
    city character varying(120),
    district character varying(120),
    state character varying(120),
    country character varying(120) DEFAULT 'India'::character varying NOT NULL,
    pin_code character varying(10),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT student_addresses_address_type_check CHECK (((address_type)::text = ANY (ARRAY[('Present'::character varying)::text, ('Permanent'::character varying)::text])))
);


--
-- Name: student_addresses_student_address_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_addresses_student_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_addresses_student_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_addresses_student_address_id_seq OWNED BY public.student_addresses.student_address_id;


--
-- Name: student_attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_attendance (
    attendance_id bigint NOT NULL,
    attendance_session_id bigint NOT NULL,
    student_id bigint NOT NULL,
    attendance_status character varying(10) NOT NULL,
    remarks character varying(250),
    marked_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT student_attendance_attendance_status_check CHECK (((attendance_status)::text = ANY (ARRAY[('P'::character varying)::text, ('A'::character varying)::text, ('L'::character varying)::text, ('OD'::character varying)::text, ('ML'::character varying)::text])))
);


--
-- Name: student_attendance_attendance_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_attendance_attendance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_attendance_attendance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_attendance_attendance_id_seq OWNED BY public.student_attendance.attendance_id;


--
-- Name: student_attendance_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_attendance_entries (
    attendance_entry_id bigint NOT NULL,
    subject_teacher_allocation_id bigint NOT NULL,
    attendance_date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    topic_covered text NOT NULL,
    student_group character varying(30) DEFAULT 'ALL'::character varying NOT NULL,
    strength integer DEFAULT 0 NOT NULL,
    present_count integer DEFAULT 0 NOT NULL,
    absent_count integer DEFAULT 0 NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT student_attendance_entries_absent_count_check CHECK ((absent_count >= 0)),
    CONSTRAINT student_attendance_entries_check CHECK ((end_time > start_time)),
    CONSTRAINT student_attendance_entries_present_count_check CHECK ((present_count >= 0))
);


--
-- Name: student_attendance_entries_attendance_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_attendance_entries_attendance_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_attendance_entries_attendance_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_attendance_entries_attendance_entry_id_seq OWNED BY public.student_attendance_entries.attendance_entry_id;


--
-- Name: student_attendance_entry_students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_attendance_entry_students (
    attendance_entry_id bigint NOT NULL,
    student_id bigint NOT NULL,
    attendance_status character varying(15) DEFAULT 'ABSENT'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT student_attendance_entry_students_attendance_status_check CHECK (((attendance_status)::text = ANY ((ARRAY['PRESENT'::character varying, 'ABSENT'::character varying])::text[])))
);


--
-- Name: student_branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_branches (
    branch_id bigint NOT NULL,
    department_id bigint NOT NULL,
    programme_id bigint NOT NULL,
    branch_code character varying(30) NOT NULL,
    branch_name character varying(150) NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: student_branches_branch_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_branches_branch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_branches_branch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_branches_branch_id_seq OWNED BY public.student_branches.branch_id;


--
-- Name: student_course_registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_course_registrations (
    registration_id bigint NOT NULL,
    student_id bigint NOT NULL,
    offering_id bigint NOT NULL,
    registration_type character varying(30) DEFAULT 'REGULAR'::character varying NOT NULL,
    registered_at timestamp with time zone DEFAULT now() NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL
);


--
-- Name: student_course_registrations_registration_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_course_registrations_registration_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_course_registrations_registration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_course_registrations_registration_id_seq OWNED BY public.student_course_registrations.registration_id;


--
-- Name: student_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_documents (
    student_document_id bigint NOT NULL,
    student_id bigint NOT NULL,
    document_type character varying(80) NOT NULL,
    document_number character varying(100),
    file_url text NOT NULL,
    verification_status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL,
    verified_by bigint,
    verified_at timestamp with time zone,
    document_type_value_id bigint,
    file_name character varying(255),
    mime_type character varying(100),
    file_size bigint,
    issue_date date,
    expiry_date date,
    is_verified boolean DEFAULT false NOT NULL,
    uploaded_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    uploaded_by bigint,
    remarks text
);


--
-- Name: student_documents_student_document_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_documents_student_document_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_documents_student_document_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_documents_student_document_id_seq OWNED BY public.student_documents.student_document_id;


--
-- Name: student_fee_demands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_fee_demands (
    demand_id bigint NOT NULL,
    student_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    term_id bigint,
    fee_head_id bigint NOT NULL,
    demand_amount numeric(14,2) NOT NULL,
    concession_amount numeric(14,2) DEFAULT 0 NOT NULL,
    fine_amount numeric(14,2) DEFAULT 0 NOT NULL,
    paid_amount numeric(14,2) DEFAULT 0 NOT NULL,
    due_date date,
    status character varying(20) DEFAULT 'DUE'::character varying NOT NULL
);


--
-- Name: student_fee_demands_demand_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_fee_demands_demand_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_fee_demands_demand_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_fee_demands_demand_id_seq OWNED BY public.student_fee_demands.demand_id;


--
-- Name: student_fee_undertakings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_fee_undertakings (
    student_fee_undertaking_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    student_id bigint NOT NULL,
    academic_year_id bigint,
    fee_category_value_id bigint,
    outstanding_amount numeric(12,2) NOT NULL,
    undertaking_amount numeric(12,2) NOT NULL,
    promise_payment_date date NOT NULL,
    undertaking_given_by character varying(20) NOT NULL,
    person_name character varying(150) NOT NULL,
    relationship character varying(80),
    mobile_number character varying(20),
    reason_for_delay text,
    undertaking_statement text,
    document_url character varying(500),
    witness_employee_id bigint,
    undertaking_status character varying(30) DEFAULT 'Pending'::character varying NOT NULL,
    reviewed_by bigint,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT student_fee_undertakings_outstanding_amount_check CHECK ((outstanding_amount >= (0)::numeric)),
    CONSTRAINT student_fee_undertakings_undertaking_amount_check CHECK ((undertaking_amount > (0)::numeric)),
    CONSTRAINT student_fee_undertakings_undertaking_given_by_check CHECK (((undertaking_given_by)::text = ANY (ARRAY[('Student'::character varying)::text, ('Parent'::character varying)::text, ('Guardian'::character varying)::text]))),
    CONSTRAINT student_fee_undertakings_undertaking_status_check CHECK (((undertaking_status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('Partially Paid'::character varying)::text, ('Paid'::character varying)::text, ('Overdue'::character varying)::text, ('Cancelled'::character varying)::text])))
);


--
-- Name: student_fee_undertakings_student_fee_undertaking_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_fee_undertakings_student_fee_undertaking_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_fee_undertakings_student_fee_undertaking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_fee_undertakings_student_fee_undertaking_id_seq OWNED BY public.student_fee_undertakings.student_fee_undertaking_id;


--
-- Name: student_guardians; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_guardians (
    student_id bigint NOT NULL,
    guardian_id bigint NOT NULL,
    is_primary boolean DEFAULT false NOT NULL
);


--
-- Name: student_import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_import_batches (
    student_import_batch_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    academic_year_id bigint,
    source_file_name character varying(255),
    source_file_url character varying(500),
    total_rows integer DEFAULT 0 NOT NULL,
    successful_rows integer DEFAULT 0 NOT NULL,
    failed_rows integer DEFAULT 0 NOT NULL,
    import_status character varying(25) DEFAULT 'Uploaded'::character varying NOT NULL,
    error_details jsonb DEFAULT '[]'::jsonb NOT NULL,
    imported_by bigint,
    imported_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT student_import_batches_failed_rows_check CHECK ((failed_rows >= 0)),
    CONSTRAINT student_import_batches_import_status_check CHECK (((import_status)::text = ANY (ARRAY[('Uploaded'::character varying)::text, ('Validated'::character varying)::text, ('Imported'::character varying)::text, ('Partially Imported'::character varying)::text, ('Failed'::character varying)::text]))),
    CONSTRAINT student_import_batches_successful_rows_check CHECK ((successful_rows >= 0)),
    CONSTRAINT student_import_batches_total_rows_check CHECK ((total_rows >= 0))
);


--
-- Name: student_import_batches_student_import_batch_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_import_batches_student_import_batch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_import_batches_student_import_batch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_import_batches_student_import_batch_id_seq OWNED BY public.student_import_batches.student_import_batch_id;


--
-- Name: student_issues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_issues (
    student_issue_id bigint NOT NULL,
    student_id bigint NOT NULL,
    reported_by bigint,
    assigned_to bigint,
    issue_category character varying(50) NOT NULL,
    issue_title character varying(200) NOT NULL,
    issue_description text,
    priority character varying(20) DEFAULT 'MEDIUM'::character varying NOT NULL,
    status character varying(20) DEFAULT 'OPEN'::character varying NOT NULL,
    reported_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone
);


--
-- Name: student_issues_student_issue_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_issues_student_issue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_issues_student_issue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_issues_student_issue_id_seq OWNED BY public.student_issues.student_issue_id;


--
-- Name: student_login_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_login_actions (
    student_login_action_id bigint NOT NULL,
    student_id bigint NOT NULL,
    user_id bigint,
    action_type character varying(40) NOT NULL,
    previous_status character varying(80),
    new_status character varying(80),
    reason text,
    action_by bigint,
    action_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ip_address inet,
    CONSTRAINT student_login_actions_action_type_check CHECK (((action_type)::text = ANY (ARRAY[('UNLOCK'::character varying)::text, ('ENABLE_LOGIN'::character varying)::text, ('DISABLE_LOGIN'::character varying)::text, ('CLEAR_FAILED_ATTEMPTS'::character varying)::text, ('RESET_LOGIN'::character varying)::text])))
);


--
-- Name: student_login_actions_student_login_action_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_login_actions_student_login_action_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_login_actions_student_login_action_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_login_actions_student_login_action_id_seq OWNED BY public.student_login_actions.student_login_action_id;


--
-- Name: student_marks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_marks (
    mark_id bigint NOT NULL,
    assessment_id bigint NOT NULL,
    student_id bigint NOT NULL,
    marks_obtained numeric(7,2),
    is_absent boolean DEFAULT false NOT NULL,
    is_malpractice boolean DEFAULT false NOT NULL,
    remarks character varying(250),
    entered_by bigint,
    entered_at timestamp with time zone DEFAULT now() NOT NULL,
    verified_by bigint,
    verified_at timestamp with time zone
);


--
-- Name: student_marks_mark_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_marks_mark_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_marks_mark_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_marks_mark_id_seq OWNED BY public.student_marks.mark_id;


--
-- Name: student_mentor_allotments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentor_allotments (
    mentor_allotment_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    student_id bigint NOT NULL,
    mentor_id bigint NOT NULL,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    is_primary boolean DEFAULT true NOT NULL,
    allotment_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    remarks text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    programme_id bigint NOT NULL,
    programme_batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    programme_section_id bigint NOT NULL,
    allotted_date date DEFAULT CURRENT_DATE NOT NULL,
    status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    CONSTRAINT student_mentor_allotments_allotment_status_check CHECK (((allotment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Transferred'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
    CONSTRAINT student_mentor_allotments_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from))),
    CONSTRAINT student_mentor_allotments_status_check CHECK (((status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Transferred'::character varying)::text])))
);


--
-- Name: student_mentor_allotments_student_mentor_allotment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_mentor_allotments_student_mentor_allotment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentor_allotments_student_mentor_allotment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_mentor_allotments_student_mentor_allotment_id_seq OWNED BY public.student_mentor_allotments.mentor_allotment_id;


--
-- Name: student_mentor_transfer_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentor_transfer_history (
    student_mentor_transfer_history_id bigint NOT NULL,
    student_id bigint NOT NULL,
    previous_mentor_employee_id bigint,
    new_mentor_employee_id bigint NOT NULL,
    transfer_date date DEFAULT CURRENT_DATE NOT NULL,
    transfer_reason text,
    transferred_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: student_mentor_transfer_histo_student_mentor_transfer_histo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_mentor_transfer_histo_student_mentor_transfer_histo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentor_transfer_histo_student_mentor_transfer_histo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_mentor_transfer_histo_student_mentor_transfer_histo_seq OWNED BY public.student_mentor_transfer_history.student_mentor_transfer_history_id;


--
-- Name: student_mentoring_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentoring_attachments (
    student_mentoring_attachment_id bigint NOT NULL,
    student_mentoring_session_id bigint,
    student_fee_undertaking_id bigint,
    file_name character varying(255) NOT NULL,
    file_url character varying(500) NOT NULL,
    mime_type character varying(100),
    file_size bigint,
    description character varying(250),
    uploaded_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    uploaded_by bigint,
    CONSTRAINT student_mentoring_attachments_check CHECK (((student_mentoring_session_id IS NOT NULL) OR (student_fee_undertaking_id IS NOT NULL)))
);


--
-- Name: student_mentoring_attachments_student_mentoring_attachment__seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_mentoring_attachments_student_mentoring_attachment__seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentoring_attachments_student_mentoring_attachment__seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_mentoring_attachments_student_mentoring_attachment__seq OWNED BY public.student_mentoring_attachments.student_mentoring_attachment_id;


--
-- Name: student_mentoring_followups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentoring_followups (
    student_mentoring_followup_id bigint NOT NULL,
    student_mentoring_session_id bigint NOT NULL,
    followup_date date NOT NULL,
    followup_notes text NOT NULL,
    student_response text,
    action_status character varying(30) DEFAULT 'Pending'::character varying NOT NULL,
    next_followup_date date,
    completed_by bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    CONSTRAINT student_mentoring_followups_action_status_check CHECK (((action_status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('In Progress'::character varying)::text, ('Resolved'::character varying)::text, ('Escalated'::character varying)::text, ('Closed'::character varying)::text])))
);


--
-- Name: student_mentoring_followups_student_mentoring_followup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_mentoring_followups_student_mentoring_followup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentoring_followups_student_mentoring_followup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_mentoring_followups_student_mentoring_followup_id_seq OWNED BY public.student_mentoring_followups.student_mentoring_followup_id;


--
-- Name: student_mentoring_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentoring_reviews (
    student_mentoring_review_id bigint NOT NULL,
    student_mentoring_session_id bigint NOT NULL,
    student_reviewer_allotment_id bigint,
    reviewer_employee_id bigint NOT NULL,
    review_level smallint DEFAULT 1 NOT NULL,
    reviewer_remarks text NOT NULL,
    recommendation character varying(40) DEFAULT 'No Action'::character varying NOT NULL,
    next_review_date date,
    review_status character varying(20) DEFAULT 'Reviewed'::character varying NOT NULL,
    reviewed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    CONSTRAINT student_mentoring_reviews_recommendation_check CHECK (((recommendation)::text = ANY (ARRAY[('No Action'::character varying)::text, ('Follow-up'::character varying)::text, ('Escalate'::character varying)::text, ('Refer to HOD'::character varying)::text, ('Refer to Management'::character varying)::text, ('Close'::character varying)::text]))),
    CONSTRAINT student_mentoring_reviews_review_level_check CHECK ((review_level >= 1)),
    CONSTRAINT student_mentoring_reviews_review_status_check CHECK (((review_status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('Reviewed'::character varying)::text, ('Escalated'::character varying)::text, ('Closed'::character varying)::text])))
);


--
-- Name: student_mentoring_reviews_student_mentoring_review_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_mentoring_reviews_student_mentoring_review_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentoring_reviews_student_mentoring_review_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_mentoring_reviews_student_mentoring_review_id_seq OWNED BY public.student_mentoring_reviews.student_mentoring_review_id;


--
-- Name: student_mentoring_session_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentoring_session_topics (
    student_mentoring_session_id bigint NOT NULL,
    mentoring_topic_id bigint NOT NULL,
    remarks text
);


--
-- Name: student_mentoring_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_mentoring_sessions (
    student_mentoring_session_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    academic_year_id bigint,
    student_id bigint NOT NULL,
    mentor_employee_id bigint NOT NULL,
    student_mentor_allotment_id bigint,
    mentoring_date date DEFAULT CURRENT_DATE NOT NULL,
    session_type character varying(40) NOT NULL,
    meeting_mode character varying(20) DEFAULT 'Offline'::character varying NOT NULL,
    priority character varying(20) DEFAULT 'Normal'::character varying NOT NULL,
    problem_identified text,
    mentor_observation text,
    advice_action_taken text,
    follow_up_required boolean DEFAULT false NOT NULL,
    follow_up_date date,
    referral_required boolean DEFAULT false NOT NULL,
    referred_employee_id bigint,
    referred_department_id bigint,
    student_present boolean DEFAULT true NOT NULL,
    parent_contacted boolean DEFAULT false NOT NULL,
    is_confidential boolean DEFAULT false NOT NULL,
    session_status character varying(25) DEFAULT 'Completed'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT student_mentoring_sessions_check CHECK (((follow_up_required = false) OR (follow_up_date IS NOT NULL))),
    CONSTRAINT student_mentoring_sessions_meeting_mode_check CHECK (((meeting_mode)::text = ANY (ARRAY[('Offline'::character varying)::text, ('Online'::character varying)::text, ('Telephone'::character varying)::text]))),
    CONSTRAINT student_mentoring_sessions_priority_check CHECK (((priority)::text = ANY (ARRAY[('Low'::character varying)::text, ('Normal'::character varying)::text, ('High'::character varying)::text, ('Urgent'::character varying)::text]))),
    CONSTRAINT student_mentoring_sessions_session_status_check CHECK (((session_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Completed'::character varying)::text, ('Follow-up Pending'::character varying)::text, ('Closed'::character varying)::text]))),
    CONSTRAINT student_mentoring_sessions_session_type_check CHECK (((session_type)::text = ANY (ARRAY[('Academic'::character varying)::text, ('Attendance'::character varying)::text, ('Behaviour'::character varying)::text, ('Discipline'::character varying)::text, ('Fees'::character varying)::text, ('Personal'::character varying)::text, ('Family'::character varying)::text, ('Career'::character varying)::text, ('Placement'::character varying)::text, ('Health'::character varying)::text, ('General'::character varying)::text])))
);


--
-- Name: student_mentoring_sessions_student_mentoring_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_mentoring_sessions_student_mentoring_session_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_mentoring_sessions_student_mentoring_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_mentoring_sessions_student_mentoring_session_id_seq OWNED BY public.student_mentoring_sessions.student_mentoring_session_id;


--
-- Name: student_parents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_parents (
    student_parent_id bigint NOT NULL,
    student_id bigint NOT NULL,
    father_name character varying(150),
    father_mobile character varying(20),
    father_email character varying(150),
    father_occupation character varying(150),
    mother_name character varying(150),
    mother_mobile character varying(20),
    mother_email character varying(150),
    mother_occupation character varying(150),
    guardian_name character varying(150),
    guardian_relationship character varying(80),
    guardian_mobile character varying(20),
    guardian_email character varying(150),
    annual_family_income numeric(14,2),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT student_parents_annual_family_income_check CHECK (((annual_family_income IS NULL) OR (annual_family_income >= (0)::numeric)))
);


--
-- Name: student_parents_student_parent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_parents_student_parent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_parents_student_parent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_parents_student_parent_id_seq OWNED BY public.student_parents.student_parent_id;


--
-- Name: student_password_reset_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_password_reset_audit (
    student_password_reset_audit_id bigint NOT NULL,
    student_id bigint NOT NULL,
    user_id bigint,
    reset_method character varying(30) NOT NULL,
    force_password_change boolean DEFAULT true NOT NULL,
    reason text,
    reset_by bigint,
    reset_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ip_address inet,
    CONSTRAINT student_password_reset_audit_reset_method_check CHECK (((reset_method)::text = ANY (ARRAY[('EMAIL_LINK'::character varying)::text, ('TEMPORARY_PASSWORD'::character varying)::text, ('ADMIN_RESET'::character varying)::text])))
);


--
-- Name: student_password_reset_audit_student_password_reset_audit_i_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_password_reset_audit_student_password_reset_audit_i_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_password_reset_audit_student_password_reset_audit_i_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_password_reset_audit_student_password_reset_audit_i_seq OWNED BY public.student_password_reset_audit.student_password_reset_audit_id;


--
-- Name: student_registration_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_registration_history (
    student_registration_history_id bigint NOT NULL,
    student_id bigint NOT NULL,
    old_registration_number character varying(60),
    new_registration_number character varying(60) NOT NULL,
    reason text NOT NULL,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: student_registration_history_student_registration_history_i_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_registration_history_student_registration_history_i_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_registration_history_student_registration_history_i_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_registration_history_student_registration_history_i_seq OWNED BY public.student_registration_history.student_registration_history_id;


--
-- Name: student_restore_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_restore_history (
    student_restore_history_id bigint NOT NULL,
    student_id bigint NOT NULL,
    previous_status_id bigint,
    restored_status_id bigint,
    restore_reason text,
    restored_by bigint,
    restored_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ip_address inet
);


--
-- Name: student_restore_history_student_restore_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_restore_history_student_restore_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_restore_history_student_restore_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_restore_history_student_restore_history_id_seq OWNED BY public.student_restore_history.student_restore_history_id;


--
-- Name: student_reviewer_allotments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_reviewer_allotments (
    student_reviewer_allotment_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    department_id bigint,
    programme_id bigint,
    semester_id bigint,
    reviewer_employee_id bigint NOT NULL,
    review_level smallint DEFAULT 1 NOT NULL,
    applicable_to character varying(30) DEFAULT 'All Students'::character varying NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    remarks text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint,
    CONSTRAINT student_reviewer_allotments_applicable_to_check CHECK (((applicable_to)::text = ANY (ARRAY[('All Students'::character varying)::text, ('Selected Mentors'::character varying)::text, ('Selected Students'::character varying)::text]))),
    CONSTRAINT student_reviewer_allotments_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from))),
    CONSTRAINT student_reviewer_allotments_review_level_check CHECK ((review_level >= 1))
);


--
-- Name: student_reviewer_allotments_student_reviewer_allotment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_reviewer_allotments_student_reviewer_allotment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_reviewer_allotments_student_reviewer_allotment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_reviewer_allotments_student_reviewer_allotment_id_seq OWNED BY public.student_reviewer_allotments.student_reviewer_allotment_id;


--
-- Name: student_scholarships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_scholarships (
    student_scholarship_id bigint NOT NULL,
    student_id bigint NOT NULL,
    scholarship_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    amount numeric(14,2),
    application_number character varying(100),
    status character varying(30) DEFAULT 'APPLIED'::character varying NOT NULL
);


--
-- Name: student_scholarships_student_scholarship_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_scholarships_student_scholarship_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_scholarships_student_scholarship_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_scholarships_student_scholarship_id_seq OWNED BY public.student_scholarships.student_scholarship_id;


--
-- Name: student_section_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_section_history (
    history_id bigint NOT NULL,
    student_id bigint NOT NULL,
    section_id bigint NOT NULL,
    from_date date NOT NULL,
    to_date date,
    reason text
);


--
-- Name: student_section_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_section_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_section_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_section_history_history_id_seq OWNED BY public.student_section_history.history_id;


--
-- Name: student_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_status_history (
    student_status_history_id bigint NOT NULL,
    student_id bigint NOT NULL,
    old_status_id bigint,
    new_status_id bigint NOT NULL,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    reason text,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: student_status_history_student_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_status_history_student_status_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_status_history_student_status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_status_history_student_status_history_id_seq OWNED BY public.student_status_history.student_status_history_id;


--
-- Name: student_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_statuses (
    student_status_id bigint NOT NULL,
    institute_id bigint NOT NULL,
    status_code character varying(30) NOT NULL,
    status_name character varying(100) NOT NULL,
    description text,
    display_order integer DEFAULT 0 NOT NULL,
    is_terminal boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: student_statuses_student_status_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_statuses_student_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_statuses_student_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_statuses_student_status_id_seq OWNED BY public.student_statuses.student_status_id;


--
-- Name: student_transport_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_transport_allocations (
    student_transport_id bigint NOT NULL,
    student_id bigint NOT NULL,
    route_id bigint NOT NULL,
    stop_id bigint,
    academic_year_id bigint NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL
);


--
-- Name: student_transport_allocations_student_transport_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.student_transport_allocations_student_transport_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: student_transport_allocations_student_transport_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.student_transport_allocations_student_transport_id_seq OWNED BY public.student_transport_allocations.student_transport_id;


--
-- Name: students_student_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.students_student_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: students_student_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.students_student_id_seq OWNED BY public.students.student_id;


--
-- Name: subject_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_components (
    subject_component_id bigint NOT NULL,
    subject_master_id bigint NOT NULL,
    subject_type character varying(20) NOT NULL,
    credit numeric(5,2) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone,
    CONSTRAINT subject_components_credit_check CHECK ((credit >= (0)::numeric)),
    CONSTRAINT subject_components_subject_type_check CHECK (((subject_type)::text = ANY ((ARRAY['THEORY'::character varying, 'PRACTICAL'::character varying])::text[])))
);


--
-- Name: subject_masters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_masters (
    subject_master_id bigint NOT NULL,
    subject_code character varying(30) NOT NULL,
    subject_name character varying(200) NOT NULL,
    subject_short_name character varying(50),
    subject_type character varying(30) DEFAULT 'Theory'::character varying NOT NULL,
    subject_category character varying(80) NOT NULL,
    department_id bigint,
    credit numeric(5,2) DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by bigint,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    updated_at timestamp without time zone,
    programme_id bigint,
    semester_id bigint
);


--
-- Name: subject_component_list; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.subject_component_list AS
 SELECT sm.subject_master_id,
    sc.subject_component_id,
    sm.programme_id,
    sm.semester_id,
    p.programme_code,
    s.semester_name,
    sm.subject_code,
    sm.subject_name,
    sc.subject_type,
    sc.credit,
    sm.is_active
   FROM (((public.subject_masters sm
     JOIN public.subject_components sc ON ((sc.subject_master_id = sm.subject_master_id)))
     JOIN public.programmes p ON ((p.programme_id = sm.programme_id)))
     JOIN public.semesters s ON ((s.semester_id = sm.semester_id)));


--
-- Name: subject_components_subject_component_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subject_components_subject_component_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subject_components_subject_component_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subject_components_subject_component_id_seq OWNED BY public.subject_components.subject_component_id;


--
-- Name: subject_masters_subject_master_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subject_masters_subject_master_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subject_masters_subject_master_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subject_masters_subject_master_id_seq OWNED BY public.subject_masters.subject_master_id;


--
-- Name: subject_teacher_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_teacher_allocations (
    subject_teacher_allocation_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    section_id bigint NOT NULL,
    subject_master_id bigint NOT NULL,
    employee_id bigint NOT NULL,
    allocation_role character varying(30) DEFAULT 'PRIMARY'::character varying NOT NULL,
    workload_hours numeric(5,2) NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT subject_teacher_allocations_workload_hours_check CHECK ((workload_hours > (0)::numeric))
);


--
-- Name: subject_teacher_allocations_subject_teacher_allocation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subject_teacher_allocations_subject_teacher_allocation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subject_teacher_allocations_subject_teacher_allocation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subject_teacher_allocations_subject_teacher_allocation_id_seq OWNED BY public.subject_teacher_allocations.subject_teacher_allocation_id;


--
-- Name: substitute_teacher_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.substitute_teacher_allocations (
    substitute_teacher_allocation_id bigint NOT NULL,
    subject_teacher_allocation_id bigint NOT NULL,
    original_employee_id bigint NOT NULL,
    substitute_employee_id bigint NOT NULL,
    from_date date NOT NULL,
    to_date date NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone,
    CONSTRAINT substitute_teacher_allocations_check CHECK ((to_date >= from_date)),
    CONSTRAINT substitute_teacher_allocations_check1 CHECK ((original_employee_id <> substitute_employee_id))
);


--
-- Name: substitute_teacher_allocation_substitute_teacher_allocation_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.substitute_teacher_allocation_substitute_teacher_allocation_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: substitute_teacher_allocation_substitute_teacher_allocation_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.substitute_teacher_allocation_substitute_teacher_allocation_seq OWNED BY public.substitute_teacher_allocations.substitute_teacher_allocation_id;


--
-- Name: system_menus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_menus (
    menu_id bigint NOT NULL,
    module_id bigint NOT NULL,
    parent_menu_id bigint,
    menu_code character varying(80) NOT NULL,
    menu_name character varying(120) NOT NULL,
    menu_path character varying(250),
    menu_icon character varying(100),
    display_order integer DEFAULT 0,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: system_menus_menu_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_menus_menu_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_menus_menu_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_menus_menu_id_seq OWNED BY public.system_menus.menu_id;


--
-- Name: system_modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_modules (
    module_id bigint NOT NULL,
    module_code character varying(50) NOT NULL,
    module_name character varying(100) NOT NULL,
    module_icon character varying(100),
    display_order integer DEFAULT 0,
    status boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: system_modules_module_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_modules_module_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_modules_module_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_modules_module_id_seq OWNED BY public.system_modules.module_id;


--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_settings (
    setting_id bigint NOT NULL,
    institution_id bigint,
    setting_key character varying(120) NOT NULL,
    setting_value text,
    data_type character varying(20) DEFAULT 'STRING'::character varying,
    description text,
    updated_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: system_settings_setting_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_settings_setting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_settings_setting_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_settings_setting_id_seq OWNED BY public.system_settings.setting_id;


--
-- Name: time_slots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_slots (
    time_slot_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    slot_name character varying(30) NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    slot_type character varying(20) DEFAULT 'PERIOD'::character varying,
    sort_order integer DEFAULT 0,
    CONSTRAINT time_slots_check CHECK ((end_time > start_time))
);


--
-- Name: time_slots_time_slot_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.time_slots_time_slot_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: time_slots_time_slot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.time_slots_time_slot_id_seq OWNED BY public.time_slots.time_slot_id;


--
-- Name: timetable_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.timetable_entries (
    timetable_entry_id bigint NOT NULL,
    offering_id bigint NOT NULL,
    employee_id bigint,
    room_id bigint,
    day_of_week smallint NOT NULL,
    time_slot_id bigint NOT NULL,
    effective_from date,
    effective_to date,
    class_type character varying(20) DEFAULT 'LECTURE'::character varying,
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT timetable_entries_day_of_week_check CHECK (((day_of_week >= 1) AND (day_of_week <= 7)))
);


--
-- Name: timetable_entries_timetable_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.timetable_entries_timetable_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timetable_entries_timetable_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.timetable_entries_timetable_entry_id_seq OWNED BY public.timetable_entries.timetable_entry_id;


--
-- Name: transport_routes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transport_routes (
    route_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    route_code character varying(30) NOT NULL,
    route_name character varying(100) NOT NULL,
    start_point character varying(150),
    end_point character varying(150),
    monthly_fee numeric(12,2),
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: transport_routes_route_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transport_routes_route_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transport_routes_route_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transport_routes_route_id_seq OWNED BY public.transport_routes.route_id;


--
-- Name: transport_stops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transport_stops (
    stop_id bigint NOT NULL,
    route_id bigint NOT NULL,
    stop_name character varying(150) NOT NULL,
    pickup_time time without time zone,
    drop_time time without time zone,
    stop_order integer NOT NULL,
    stop_fee numeric(12,2)
);


--
-- Name: transport_stops_stop_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transport_stops_stop_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transport_stops_stop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transport_stops_stop_id_seq OWNED BY public.transport_stops.stop_id;


--
-- Name: user_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_accounts (
    user_id bigint NOT NULL,
    employee_id bigint,
    login_id character varying(100) NOT NULL,
    password_hash text NOT NULL,
    default_login boolean DEFAULT true,
    account_status character varying(20) DEFAULT 'ACTIVE'::character varying,
    failed_login_attempts integer DEFAULT 0,
    last_login timestamp without time zone,
    password_changed_at timestamp without time zone,
    created_by bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_by bigint,
    updated_at timestamp without time zone
);


--
-- Name: user_accounts_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_accounts_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_accounts_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_accounts_user_id_seq OWNED BY public.user_accounts.user_id;


--
-- Name: user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_permissions (
    user_permission_id bigint NOT NULL,
    user_id bigint NOT NULL,
    menu_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    is_allowed boolean NOT NULL,
    valid_from timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    valid_to timestamp without time zone,
    remarks character varying(500),
    granted_by bigint,
    granted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_permissions_user_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_permissions_user_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_permissions_user_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_permissions_user_permission_id_seq OWNED BY public.user_permissions.user_permission_id;


--
-- Name: user_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_photos (
    user_photo_id bigint NOT NULL,
    user_id bigint NOT NULL,
    original_file_name character varying(255),
    stored_file_name character varying(255) NOT NULL,
    file_path text NOT NULL,
    file_type character varying(100),
    file_size_bytes bigint,
    is_current boolean DEFAULT true NOT NULL,
    uploaded_by bigint,
    uploaded_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_photos_user_photo_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_photos_user_photo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_photos_user_photo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_photos_user_photo_id_seq OWNED BY public.user_photos.user_photo_id;


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    department_id bigint NOT NULL,
    valid_from date DEFAULT CURRENT_DATE,
    valid_to date,
    assigned_by bigint
);


--
-- Name: user_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_status_history (
    user_status_history_id bigint NOT NULL,
    user_id bigint NOT NULL,
    old_status character varying(20),
    new_status character varying(20) NOT NULL,
    change_reason text,
    changed_by bigint,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_status_history_user_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_status_history_user_status_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_status_history_user_status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_status_history_user_status_history_id_seq OWNED BY public.user_status_history.user_status_history_id;


--
-- Name: user_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_types (
    user_type_id smallint NOT NULL,
    user_type_code character varying(30) NOT NULL,
    user_type_name character varying(100) NOT NULL,
    display_order integer DEFAULT 0 NOT NULL
);


--
-- Name: user_types_user_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_types_user_type_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_types_user_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_types_user_type_id_seq OWNED BY public.user_types.user_type_id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    user_id bigint NOT NULL,
    username character varying(80) NOT NULL,
    password_hash text NOT NULL,
    email character varying(150),
    mobile character varying(20),
    display_name character varying(150),
    user_type character varying(30) NOT NULL,
    must_change_password boolean DEFAULT true NOT NULL,
    last_login_at timestamp with time zone,
    failed_login_count integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    full_name character varying(200),
    user_type_id smallint,
    employee_id bigint,
    student_id bigint,
    photo_path text,
    user_status character varying(20) DEFAULT 'Active'::character varying NOT NULL,
    password_changed_at timestamp with time zone,
    remarks text,
    created_by bigint,
    updated_by bigint,
    CONSTRAINT users_employee_student_link_check CHECK ((NOT ((employee_id IS NOT NULL) AND (student_id IS NOT NULL)))),
    CONSTRAINT users_user_status_check CHECK (((user_status)::text = ANY ((ARRAY['Active'::character varying, 'Inactive'::character varying, 'Locked'::character varying, 'Suspended'::character varying])::text[])))
);


--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vehicles (
    vehicle_id bigint NOT NULL,
    institution_id bigint NOT NULL,
    registration_number character varying(30) NOT NULL,
    vehicle_type character varying(30),
    seating_capacity integer,
    driver_name character varying(100),
    driver_mobile character varying(20),
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: vehicles_vehicle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vehicles_vehicle_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vehicles_vehicle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vehicles_vehicle_id_seq OWNED BY public.vehicles.vehicle_id;


--
-- Name: user_logins user_id; Type: DEFAULT; Schema: ABDC_DB; Owner: -
--

ALTER TABLE ONLY "ABDC_DB".user_logins ALTER COLUMN user_id SET DEFAULT nextval('"ABDC_DB".user_logins_user_id_seq'::regclass);


--
-- Name: academic_breaks academic_break_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_breaks ALTER COLUMN academic_break_id SET DEFAULT nextval('academics.academic_breaks_academic_break_id_seq'::regclass);


--
-- Name: academic_periods period_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_periods ALTER COLUMN period_id SET DEFAULT nextval('academics.academic_periods_period_id_seq'::regclass);


--
-- Name: academic_time_configurations time_configuration_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configurations ALTER COLUMN time_configuration_id SET DEFAULT nextval('academics.academic_time_configurations_time_configuration_id_seq'::regclass);


--
-- Name: attendance_calendar_dates attendance_calendar_date_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_dates ALTER COLUMN attendance_calendar_date_id SET DEFAULT nextval('academics.attendance_calendar_dates_attendance_calendar_date_id_seq'::regclass);


--
-- Name: attendance_calendar_settings attendance_calendar_setting_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings ALTER COLUMN attendance_calendar_setting_id SET DEFAULT nextval('academics.attendance_calendar_settings_attendance_calendar_setting_id_seq'::regclass);


--
-- Name: attendance_calendar_weekdays attendance_calendar_weekday_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_weekdays ALTER COLUMN attendance_calendar_weekday_id SET DEFAULT nextval('academics.attendance_calendar_weekdays_attendance_calendar_weekday_id_seq'::regclass);


--
-- Name: course_outcome_codes co_code_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcome_codes ALTER COLUMN co_code_id SET DEFAULT nextval('academics.course_outcome_codes_co_code_id_seq'::regclass);


--
-- Name: course_outcomes course_outcome_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes ALTER COLUMN course_outcome_id SET DEFAULT nextval('academics.course_outcomes_course_outcome_id_seq'::regclass);


--
-- Name: faculty_subject_assignments faculty_subject_assignment_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments ALTER COLUMN faculty_subject_assignment_id SET DEFAULT nextval('academics.faculty_subject_assignments_faculty_subject_assignment_id_seq'::regclass);


--
-- Name: lecture_notes lecture_note_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lecture_notes ALTER COLUMN lecture_note_id SET DEFAULT nextval('academics.lecture_notes_lecture_note_id_seq'::regclass);


--
-- Name: lesson_plan_books lesson_plan_book_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_books ALTER COLUMN lesson_plan_book_id SET DEFAULT nextval('academics.lesson_plan_books_lesson_plan_book_id_seq'::regclass);


--
-- Name: lesson_plan_headers lesson_plan_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers ALTER COLUMN lesson_plan_id SET DEFAULT nextval('academics.lesson_plan_headers_lesson_plan_id_seq'::regclass);


--
-- Name: lesson_plan_topics lesson_plan_topic_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics ALTER COLUMN lesson_plan_topic_id SET DEFAULT nextval('academics.lesson_plan_topics_lesson_plan_topic_id_seq'::regclass);


--
-- Name: timetable_change_logs timetable_change_log_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_change_logs ALTER COLUMN timetable_change_log_id SET DEFAULT nextval('academics.timetable_change_logs_timetable_change_log_id_seq'::regclass);


--
-- Name: timetable_entries timetable_entry_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries ALTER COLUMN timetable_entry_id SET DEFAULT nextval('academics.timetable_entries_timetable_entry_id_seq'::regclass);


--
-- Name: timetable_headers timetable_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers ALTER COLUMN timetable_id SET DEFAULT nextval('academics.timetable_headers_timetable_id_seq'::regclass);


--
-- Name: timetable_working_days timetable_working_day_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_working_days ALTER COLUMN timetable_working_day_id SET DEFAULT nextval('academics.timetable_working_days_timetable_working_day_id_seq'::regclass);


--
-- Name: week_days week_day_id; Type: DEFAULT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.week_days ALTER COLUMN week_day_id SET DEFAULT nextval('academics.week_days_week_day_id_seq'::regclass);


--
-- Name: sms_batches sms_batch_id; Type: DEFAULT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_batches ALTER COLUMN sms_batch_id SET DEFAULT nextval('communication.sms_batches_sms_batch_id_seq'::regclass);


--
-- Name: sms_recipients sms_recipient_id; Type: DEFAULT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_recipients ALTER COLUMN sms_recipient_id SET DEFAULT nextval('communication.sms_recipients_sms_recipient_id_seq'::regclass);


--
-- Name: sms_templates sms_template_id; Type: DEFAULT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_templates ALTER COLUMN sms_template_id SET DEFAULT nextval('communication.sms_templates_sms_template_id_seq'::regclass);


--
-- Name: communication_modes communication_mode_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.communication_modes ALTER COLUMN communication_mode_id SET DEFAULT nextval('mentoring.communication_modes_communication_mode_id_seq'::regclass);


--
-- Name: counselling_followups counselling_followup_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_followups ALTER COLUMN counselling_followup_id SET DEFAULT nextval('mentoring.counselling_followups_counselling_followup_id_seq'::regclass);


--
-- Name: counselling_purposes counselling_purpose_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_purposes ALTER COLUMN counselling_purpose_id SET DEFAULT nextval('mentoring.counselling_purposes_counselling_purpose_id_seq'::regclass);


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remark_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks ALTER COLUMN counselling_reviewer_remark_id SET DEFAULT nextval('mentoring.counselling_reviewer_remarks_counselling_reviewer_remark_id_seq'::regclass);


--
-- Name: employee_mentor_eligibility employee_mentor_eligibility_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility ALTER COLUMN employee_mentor_eligibility_id SET DEFAULT nextval('mentoring.employee_mentor_eligibility_employee_mentor_eligibility_id_seq'::regclass);


--
-- Name: employee_mentor_eligibility_history employee_mentor_eligibility_history_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility_history ALTER COLUMN employee_mentor_eligibility_history_id SET DEFAULT nextval('mentoring.employee_mentor_eligibility_h_employee_mentor_eligibility_h_seq'::regclass);


--
-- Name: first_reviewer_remarks first_reviewer_remark_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks ALTER COLUMN first_reviewer_remark_id SET DEFAULT nextval('mentoring.first_reviewer_remarks_first_reviewer_remark_id_seq'::regclass);


--
-- Name: mentor_assignment_changes assignment_change_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes ALTER COLUMN assignment_change_id SET DEFAULT nextval('mentoring.mentor_assignment_changes_assignment_change_id_seq'::regclass);


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_detail_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details ALTER COLUMN mentor_reviewer_detail_id SET DEFAULT nextval('mentoring.mentor_reviewer_allotment_details_mentor_reviewer_detail_id_seq'::regclass);


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotment_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments ALTER COLUMN mentor_reviewer_allotment_id SET DEFAULT nextval('mentoring.mentor_reviewer_allotments_mentor_reviewer_allotment_id_seq'::regclass);


--
-- Name: mentor_reviewer_change_history mentor_reviewer_change_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_change_history ALTER COLUMN mentor_reviewer_change_id SET DEFAULT nextval('mentoring.mentor_reviewer_change_history_mentor_reviewer_change_id_seq'::regclass);


--
-- Name: mentors mentor_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors ALTER COLUMN mentor_id SET DEFAULT nextval('mentoring.mentors_mentor_id_seq'::regclass);


--
-- Name: parent_interactions parent_interaction_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions ALTER COLUMN parent_interaction_id SET DEFAULT nextval('mentoring.parent_interactions_parent_interaction_id_seq'::regclass);


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotment_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.prospective_student_mentor_allotments ALTER COLUMN prospective_student_mentor_allotment_id SET DEFAULT nextval('mentoring.prospective_student_mentor_al_prospective_student_mentor_al_seq'::regclass);


--
-- Name: reviewers reviewer_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.reviewers ALTER COLUMN reviewer_id SET DEFAULT nextval('mentoring.reviewers_reviewer_id_seq'::regclass);


--
-- Name: student_counsellings student_counselling_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings ALTER COLUMN student_counselling_id SET DEFAULT nextval('mentoring.student_counsellings_student_counselling_id_seq'::regclass);


--
-- Name: student_mentor_allotments mentor_allotment_id; Type: DEFAULT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments ALTER COLUMN mentor_allotment_id SET DEFAULT nextval('mentoring.student_mentor_allotments_mentor_allotment_id_seq'::regclass);


--
-- Name: permission_change_history history_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history ALTER COLUMN history_id SET DEFAULT nextval('permission_management.permission_change_history_history_id_seq'::regclass);


--
-- Name: permissions permission_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permissions ALTER COLUMN permission_id SET DEFAULT nextval('permission_management.permissions_permission_id_seq'::regclass);


--
-- Name: role_permissions role_permission_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.role_permissions ALTER COLUMN role_permission_id SET DEFAULT nextval('permission_management.role_permissions_role_permission_id_seq'::regclass);


--
-- Name: roles role_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.roles ALTER COLUMN role_id SET DEFAULT nextval('permission_management.roles_role_id_seq'::regclass);


--
-- Name: system_menus menu_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_menus ALTER COLUMN menu_id SET DEFAULT nextval('permission_management.system_menus_menu_id_seq'::regclass);


--
-- Name: system_modules module_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_modules ALTER COLUMN module_id SET DEFAULT nextval('permission_management.system_modules_module_id_seq'::regclass);


--
-- Name: user_permissions user_permission_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions ALTER COLUMN user_permission_id SET DEFAULT nextval('permission_management.user_permissions_user_permission_id_seq'::regclass);


--
-- Name: user_roles user_role_id; Type: DEFAULT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_roles ALTER COLUMN user_role_id SET DEFAULT nextval('permission_management.user_roles_user_role_id_seq'::regclass);


--
-- Name: academic_terms term_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_terms ALTER COLUMN term_id SET DEFAULT nextval('public.academic_terms_term_id_seq'::regclass);


--
-- Name: academic_years academic_year_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years ALTER COLUMN academic_year_id SET DEFAULT nextval('public.academic_years_academic_year_id_seq'::regclass);


--
-- Name: admission_batches batch_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_batches ALTER COLUMN batch_id SET DEFAULT nextval('public.admission_batches_batch_id_seq'::regclass);


--
-- Name: admission_categories admission_category_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories ALTER COLUMN admission_category_id SET DEFAULT nextval('public.admission_categories_admission_category_id_seq'::regclass);


--
-- Name: approval_actions approval_action_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_actions ALTER COLUMN approval_action_id SET DEFAULT nextval('public.approval_actions_approval_action_id_seq'::regclass);


--
-- Name: approval_requests approval_request_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests ALTER COLUMN approval_request_id SET DEFAULT nextval('public.approval_requests_approval_request_id_seq'::regclass);


--
-- Name: assessment_components assessment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_components ALTER COLUMN assessment_id SET DEFAULT nextval('public.assessment_components_assessment_id_seq'::regclass);


--
-- Name: attendance_sessions attendance_session_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_sessions ALTER COLUMN attendance_session_id SET DEFAULT nextval('public.attendance_sessions_attendance_session_id_seq'::regclass);


--
-- Name: audit_logs audit_log_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN audit_log_id SET DEFAULT nextval('public.audit_logs_audit_log_id_seq'::regclass);


--
-- Name: batch_section_assignments assignment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_section_assignments ALTER COLUMN assignment_id SET DEFAULT nextval('public.batch_section_assignments_assignment_id_seq'::regclass);


--
-- Name: buildings building_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings ALTER COLUMN building_id SET DEFAULT nextval('public.buildings_building_id_seq'::regclass);


--
-- Name: campuses campus_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campuses ALTER COLUMN campus_id SET DEFAULT nextval('public.campuses_campus_id_seq'::regclass);


--
-- Name: class_teacher_allocations class_teacher_allocation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations ALTER COLUMN class_teacher_allocation_id SET DEFAULT nextval('public.class_teacher_allocations_class_teacher_allocation_id_seq'::regclass);


--
-- Name: classroom_facility_masters facility_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facility_masters ALTER COLUMN facility_id SET DEFAULT nextval('public.classroom_facility_masters_facility_id_seq'::regclass);


--
-- Name: classroom_types classroom_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_types ALTER COLUMN classroom_type_id SET DEFAULT nextval('public.classroom_types_classroom_type_id_seq'::regclass);


--
-- Name: classroom_unavailability classroom_unavailability_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_unavailability ALTER COLUMN classroom_unavailability_id SET DEFAULT nextval('public.classroom_unavailability_classroom_unavailability_id_seq'::regclass);


--
-- Name: classrooms classroom_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms ALTER COLUMN classroom_id SET DEFAULT nextval('public.classrooms_classroom_id_seq'::regclass);


--
-- Name: common_master_types master_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_types ALTER COLUMN master_type_id SET DEFAULT nextval('public.common_master_types_master_type_id_seq'::regclass);


--
-- Name: common_master_values master_value_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values ALTER COLUMN master_value_id SET DEFAULT nextval('public.common_master_values_master_value_id_seq'::regclass);


--
-- Name: course_offerings offering_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_offerings ALTER COLUMN offering_id SET DEFAULT nextval('public.course_offerings_offering_id_seq'::regclass);


--
-- Name: course_results course_result_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_results ALTER COLUMN course_result_id SET DEFAULT nextval('public.course_results_course_result_id_seq'::regclass);


--
-- Name: courses course_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses ALTER COLUMN course_id SET DEFAULT nextval('public.courses_course_id_seq'::regclass);


--
-- Name: curriculum_courses curriculum_course_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_courses ALTER COLUMN curriculum_course_id SET DEFAULT nextval('public.curriculum_courses_curriculum_course_id_seq'::regclass);


--
-- Name: curriculum_schemes scheme_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_schemes ALTER COLUMN scheme_id SET DEFAULT nextval('public.curriculum_schemes_scheme_id_seq'::regclass);


--
-- Name: dashboard_messages dashboard_message_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_messages ALTER COLUMN dashboard_message_id SET DEFAULT nextval('public.dashboard_messages_dashboard_message_id_seq'::regclass);


--
-- Name: dashboard_notice_acknowledgments notice_acknowledgment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_acknowledgments ALTER COLUMN notice_acknowledgment_id SET DEFAULT nextval('public.dashboard_notice_acknowledgments_notice_acknowledgment_id_seq'::regclass);


--
-- Name: dashboard_notice_audiences notice_audience_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences ALTER COLUMN notice_audience_id SET DEFAULT nextval('public.dashboard_notice_audiences_notice_audience_id_seq'::regclass);


--
-- Name: dashboard_notices notice_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices ALTER COLUMN notice_id SET DEFAULT nextval('public.dashboard_notices_notice_id_seq'::regclass);


--
-- Name: departments department_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments ALTER COLUMN department_id SET DEFAULT nextval('public.departments_department_id_seq'::regclass);


--
-- Name: designations designation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designations ALTER COLUMN designation_id SET DEFAULT nextval('public.designations_designation_id_seq'::regclass);


--
-- Name: document_types document_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_types ALTER COLUMN document_type_id SET DEFAULT nextval('public.document_types_document_type_id_seq'::regclass);


--
-- Name: employee_leaves leave_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leaves ALTER COLUMN leave_id SET DEFAULT nextval('public.employee_leaves_leave_id_seq'::regclass);


--
-- Name: employee_login_history history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_login_history ALTER COLUMN history_id SET DEFAULT nextval('public.employee_login_history_history_id_seq'::regclass);


--
-- Name: employee_qualifications qualification_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_qualifications ALTER COLUMN qualification_id SET DEFAULT nextval('public.employee_qualifications_qualification_id_seq'::regclass);


--
-- Name: employees employee_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees ALTER COLUMN employee_id SET DEFAULT nextval('public.employees_employee_id_seq'::regclass);


--
-- Name: exam_types exam_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types ALTER COLUMN exam_type_id SET DEFAULT nextval('public.exam_types_exam_type_id_seq'::regclass);


--
-- Name: examinations examination_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.examinations ALTER COLUMN examination_id SET DEFAULT nextval('public.examinations_examination_id_seq'::regclass);


--
-- Name: faculty_course_allocations allocation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faculty_course_allocations ALTER COLUMN allocation_id SET DEFAULT nextval('public.faculty_course_allocations_allocation_id_seq'::regclass);


--
-- Name: fee_heads fee_head_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_heads ALTER COLUMN fee_head_id SET DEFAULT nextval('public.fee_heads_fee_head_id_seq'::regclass);


--
-- Name: fee_payment_allocations payment_allocation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payment_allocations ALTER COLUMN payment_allocation_id SET DEFAULT nextval('public.fee_payment_allocations_payment_allocation_id_seq'::regclass);


--
-- Name: fee_payments payment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payments ALTER COLUMN payment_id SET DEFAULT nextval('public.fee_payments_payment_id_seq'::regclass);


--
-- Name: fee_structure_items fee_structure_item_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structure_items ALTER COLUMN fee_structure_item_id SET DEFAULT nextval('public.fee_structure_items_fee_structure_item_id_seq'::regclass);


--
-- Name: fee_structures fee_structure_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structures ALTER COLUMN fee_structure_id SET DEFAULT nextval('public.fee_structures_fee_structure_id_seq'::regclass);


--
-- Name: file_attachments attachment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file_attachments ALTER COLUMN attachment_id SET DEFAULT nextval('public.file_attachments_attachment_id_seq'::regclass);


--
-- Name: grade_scales grade_scale_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales ALTER COLUMN grade_scale_id SET DEFAULT nextval('public.grade_scales_grade_scale_id_seq'::regclass);


--
-- Name: grievance_actions grievance_action_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievance_actions ALTER COLUMN grievance_action_id SET DEFAULT nextval('public.grievance_actions_grievance_action_id_seq'::regclass);


--
-- Name: grievances grievance_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievances ALTER COLUMN grievance_id SET DEFAULT nextval('public.grievances_grievance_id_seq'::regclass);


--
-- Name: guardians guardian_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardians ALTER COLUMN guardian_id SET DEFAULT nextval('public.guardians_guardian_id_seq'::regclass);


--
-- Name: hostel_allocations hostel_allocation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_allocations ALTER COLUMN hostel_allocation_id SET DEFAULT nextval('public.hostel_allocations_hostel_allocation_id_seq'::regclass);


--
-- Name: hostel_rooms hostel_room_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_rooms ALTER COLUMN hostel_room_id SET DEFAULT nextval('public.hostel_rooms_hostel_room_id_seq'::regclass);


--
-- Name: hostels hostel_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostels ALTER COLUMN hostel_id SET DEFAULT nextval('public.hostels_hostel_id_seq'::regclass);


--
-- Name: institutions institution_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.institutions ALTER COLUMN institution_id SET DEFAULT nextval('public.institutions_institution_id_seq'::regclass);


--
-- Name: issue_followups followup_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_followups ALTER COLUMN followup_id SET DEFAULT nextval('public.issue_followups_followup_id_seq'::regclass);


--
-- Name: libraries library_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.libraries ALTER COLUMN library_id SET DEFAULT nextval('public.libraries_library_id_seq'::regclass);


--
-- Name: library_almiras almira_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_almiras ALTER COLUMN almira_id SET DEFAULT nextval('public.library_almiras_almira_id_seq'::regclass);


--
-- Name: library_authors author_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_authors ALTER COLUMN author_id SET DEFAULT nextval('public.library_authors_author_id_seq'::regclass);


--
-- Name: library_book_copies book_copy_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_copies ALTER COLUMN book_copy_id SET DEFAULT nextval('public.library_book_copies_book_copy_id_seq'::regclass);


--
-- Name: library_book_issues book_issue_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_issues ALTER COLUMN book_issue_id SET DEFAULT nextval('public.library_book_issues_book_issue_id_seq'::regclass);


--
-- Name: library_books book_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books ALTER COLUMN book_id SET DEFAULT nextval('public.library_books_book_id_seq'::regclass);


--
-- Name: library_categories category_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories ALTER COLUMN category_id SET DEFAULT nextval('public.library_categories_category_id_seq'::regclass);


--
-- Name: library_issue_types issue_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_issue_types ALTER COLUMN issue_type_id SET DEFAULT nextval('public.library_issue_types_issue_type_id_seq'::regclass);


--
-- Name: library_members library_member_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_members ALTER COLUMN library_member_id SET DEFAULT nextval('public.library_members_library_member_id_seq'::regclass);


--
-- Name: library_publishers publisher_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_publishers ALTER COLUMN publisher_id SET DEFAULT nextval('public.library_publishers_publisher_id_seq'::regclass);


--
-- Name: library_purchase_invoice_items invoice_item_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoice_items ALTER COLUMN invoice_item_id SET DEFAULT nextval('public.library_purchase_invoice_items_invoice_item_id_seq'::regclass);


--
-- Name: library_purchase_invoices invoice_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices ALTER COLUMN invoice_id SET DEFAULT nextval('public.library_purchase_invoices_invoice_id_seq'::regclass);


--
-- Name: library_purchase_order_items purchase_order_item_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_order_items ALTER COLUMN purchase_order_item_id SET DEFAULT nextval('public.library_purchase_order_items_purchase_order_item_id_seq'::regclass);


--
-- Name: library_purchase_orders purchase_order_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_orders ALTER COLUMN purchase_order_id SET DEFAULT nextval('public.library_purchase_orders_purchase_order_id_seq'::regclass);


--
-- Name: library_student_members student_member_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_student_members ALTER COLUMN student_member_id SET DEFAULT nextval('public.library_student_members_student_member_id_seq'::regclass);


--
-- Name: library_study_material_issues material_issue_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_issues ALTER COLUMN material_issue_id SET DEFAULT nextval('public.library_study_material_issues_material_issue_id_seq'::regclass);


--
-- Name: library_study_material_prices price_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_prices ALTER COLUMN price_id SET DEFAULT nextval('public.library_study_material_prices_price_id_seq'::regclass);


--
-- Name: library_study_materials study_material_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials ALTER COLUMN study_material_id SET DEFAULT nextval('public.library_study_materials_study_material_id_seq'::regclass);


--
-- Name: library_subjects subject_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects ALTER COLUMN subject_id SET DEFAULT nextval('public.library_subjects_subject_id_seq'::regclass);


--
-- Name: library_suppliers supplier_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_suppliers ALTER COLUMN supplier_id SET DEFAULT nextval('public.library_suppliers_supplier_id_seq'::regclass);


--
-- Name: library_titles title_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_titles ALTER COLUMN title_id SET DEFAULT nextval('public.library_titles_title_id_seq'::regclass);


--
-- Name: library_transactions library_transaction_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_transactions ALTER COLUMN library_transaction_id SET DEFAULT nextval('public.library_transactions_library_transaction_id_seq'::regclass);


--
-- Name: login_history login_history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history ALTER COLUMN login_history_id SET DEFAULT nextval('public.login_history_login_history_id_seq'::regclass);


--
-- Name: login_logs login_log_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_logs ALTER COLUMN login_log_id SET DEFAULT nextval('public.login_logs_login_log_id_seq'::regclass);


--
-- Name: mentor_assignments mentor_assignment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_assignments ALTER COLUMN mentor_assignment_id SET DEFAULT nextval('public.mentor_assignments_mentor_assignment_id_seq'::regclass);


--
-- Name: mentor_meetings mentor_meeting_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_meetings ALTER COLUMN mentor_meeting_id SET DEFAULT nextval('public.mentor_meetings_mentor_meeting_id_seq'::regclass);


--
-- Name: mentoring_topics mentoring_topic_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentoring_topics ALTER COLUMN mentoring_topic_id SET DEFAULT nextval('public.mentoring_topics_mentoring_topic_id_seq'::regclass);


--
-- Name: notices notice_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices ALTER COLUMN notice_id SET DEFAULT nextval('public.notices_notice_id_seq'::regclass);


--
-- Name: notifications notification_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN notification_id SET DEFAULT nextval('public.notifications_notification_id_seq'::regclass);


--
-- Name: password_reset_history reset_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_history ALTER COLUMN reset_id SET DEFAULT nextval('public.password_reset_history_reset_id_seq'::regclass);


--
-- Name: permission_change_history history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history ALTER COLUMN history_id SET DEFAULT nextval('public.permission_change_history_history_id_seq'::regclass);


--
-- Name: permissions permission_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions ALTER COLUMN permission_id SET DEFAULT nextval('public.permissions_permission_id_seq'::regclass);


--
-- Name: preferred_books preferred_book_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preferred_books ALTER COLUMN preferred_book_id SET DEFAULT nextval('public.preferred_books_preferred_book_id_seq'::regclass);


--
-- Name: programme_section_merges merge_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges ALTER COLUMN merge_id SET DEFAULT nextval('public.programme_section_merges_merge_id_seq'::regclass);


--
-- Name: programme_semester_definitions programme_semester_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions ALTER COLUMN programme_semester_id SET DEFAULT nextval('public.programme_semester_definitions_programme_semester_id_seq'::regclass);


--
-- Name: programmes programme_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programmes ALTER COLUMN programme_id SET DEFAULT nextval('public.programmes_programme_id_seq'::regclass);


--
-- Name: prospective_student_followups prospective_student_followup_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_followups ALTER COLUMN prospective_student_followup_id SET DEFAULT nextval('public.prospective_student_followups_prospective_student_followup__seq'::regclass);


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_mentor_allotments ALTER COLUMN prospective_student_mentor_allotment_id SET DEFAULT nextval('public.prospective_student_mentor_al_prospective_student_mentor_al_seq'::regclass);


--
-- Name: prospective_students prospective_student_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students ALTER COLUMN prospective_student_id SET DEFAULT nextval('public.prospective_students_prospective_student_id_seq'::regclass);


--
-- Name: roles role_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN role_id SET DEFAULT nextval('public.roles_role_id_seq'::regclass);


--
-- Name: rooms room_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms ALTER COLUMN room_id SET DEFAULT nextval('public.rooms_room_id_seq'::regclass);


--
-- Name: route_vehicle_assignments assignment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_vehicle_assignments ALTER COLUMN assignment_id SET DEFAULT nextval('public.route_vehicle_assignments_assignment_id_seq'::regclass);


--
-- Name: scholarships scholarship_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scholarships ALTER COLUMN scholarship_id SET DEFAULT nextval('public.scholarships_scholarship_id_seq'::regclass);


--
-- Name: section_definitions section_definition_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_definitions ALTER COLUMN section_definition_id SET DEFAULT nextval('public.section_definitions_section_definition_id_seq'::regclass);


--
-- Name: section_masters section_master_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_masters ALTER COLUMN section_master_id SET DEFAULT nextval('public.section_masters_section_master_id_seq'::regclass);


--
-- Name: section_merge_groups merge_group_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_merge_groups ALTER COLUMN merge_group_id SET DEFAULT nextval('public.section_merge_groups_merge_group_id_seq'::regclass);


--
-- Name: sections section_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections ALTER COLUMN section_id SET DEFAULT nextval('public.sections_section_id_seq'::regclass);


--
-- Name: semester_results semester_result_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semester_results ALTER COLUMN semester_result_id SET DEFAULT nextval('public.semester_results_semester_result_id_seq'::regclass);


--
-- Name: semesters semester_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters ALTER COLUMN semester_id SET DEFAULT nextval('public.semesters_semester_id_seq'::regclass);


--
-- Name: student_academic_history history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_academic_history ALTER COLUMN history_id SET DEFAULT nextval('public.student_academic_history_history_id_seq'::regclass);


--
-- Name: student_addresses student_address_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_addresses ALTER COLUMN student_address_id SET DEFAULT nextval('public.student_addresses_student_address_id_seq'::regclass);


--
-- Name: student_attendance attendance_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance ALTER COLUMN attendance_id SET DEFAULT nextval('public.student_attendance_attendance_id_seq'::regclass);


--
-- Name: student_attendance_entries attendance_entry_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entries ALTER COLUMN attendance_entry_id SET DEFAULT nextval('public.student_attendance_entries_attendance_entry_id_seq'::regclass);


--
-- Name: student_branches branch_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_branches ALTER COLUMN branch_id SET DEFAULT nextval('public.student_branches_branch_id_seq'::regclass);


--
-- Name: student_course_registrations registration_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_course_registrations ALTER COLUMN registration_id SET DEFAULT nextval('public.student_course_registrations_registration_id_seq'::regclass);


--
-- Name: student_documents student_document_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents ALTER COLUMN student_document_id SET DEFAULT nextval('public.student_documents_student_document_id_seq'::regclass);


--
-- Name: student_fee_demands demand_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_demands ALTER COLUMN demand_id SET DEFAULT nextval('public.student_fee_demands_demand_id_seq'::regclass);


--
-- Name: student_fee_undertakings student_fee_undertaking_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings ALTER COLUMN student_fee_undertaking_id SET DEFAULT nextval('public.student_fee_undertakings_student_fee_undertaking_id_seq'::regclass);


--
-- Name: student_import_batches student_import_batch_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_import_batches ALTER COLUMN student_import_batch_id SET DEFAULT nextval('public.student_import_batches_student_import_batch_id_seq'::regclass);


--
-- Name: student_issues student_issue_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_issues ALTER COLUMN student_issue_id SET DEFAULT nextval('public.student_issues_student_issue_id_seq'::regclass);


--
-- Name: student_login_actions student_login_action_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_login_actions ALTER COLUMN student_login_action_id SET DEFAULT nextval('public.student_login_actions_student_login_action_id_seq'::regclass);


--
-- Name: student_marks mark_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks ALTER COLUMN mark_id SET DEFAULT nextval('public.student_marks_mark_id_seq'::regclass);


--
-- Name: student_mentor_allotments mentor_allotment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments ALTER COLUMN mentor_allotment_id SET DEFAULT nextval('public.student_mentor_allotments_student_mentor_allotment_id_seq'::regclass);


--
-- Name: student_mentor_transfer_history student_mentor_transfer_history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_transfer_history ALTER COLUMN student_mentor_transfer_history_id SET DEFAULT nextval('public.student_mentor_transfer_histo_student_mentor_transfer_histo_seq'::regclass);


--
-- Name: student_mentoring_attachments student_mentoring_attachment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_attachments ALTER COLUMN student_mentoring_attachment_id SET DEFAULT nextval('public.student_mentoring_attachments_student_mentoring_attachment__seq'::regclass);


--
-- Name: student_mentoring_followups student_mentoring_followup_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_followups ALTER COLUMN student_mentoring_followup_id SET DEFAULT nextval('public.student_mentoring_followups_student_mentoring_followup_id_seq'::regclass);


--
-- Name: student_mentoring_reviews student_mentoring_review_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews ALTER COLUMN student_mentoring_review_id SET DEFAULT nextval('public.student_mentoring_reviews_student_mentoring_review_id_seq'::regclass);


--
-- Name: student_mentoring_sessions student_mentoring_session_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions ALTER COLUMN student_mentoring_session_id SET DEFAULT nextval('public.student_mentoring_sessions_student_mentoring_session_id_seq'::regclass);


--
-- Name: student_parents student_parent_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents ALTER COLUMN student_parent_id SET DEFAULT nextval('public.student_parents_student_parent_id_seq'::regclass);


--
-- Name: student_password_reset_audit student_password_reset_audit_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_password_reset_audit ALTER COLUMN student_password_reset_audit_id SET DEFAULT nextval('public.student_password_reset_audit_student_password_reset_audit_i_seq'::regclass);


--
-- Name: student_registration_history student_registration_history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_registration_history ALTER COLUMN student_registration_history_id SET DEFAULT nextval('public.student_registration_history_student_registration_history_i_seq'::regclass);


--
-- Name: student_restore_history student_restore_history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_restore_history ALTER COLUMN student_restore_history_id SET DEFAULT nextval('public.student_restore_history_student_restore_history_id_seq'::regclass);


--
-- Name: student_reviewer_allotments student_reviewer_allotment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments ALTER COLUMN student_reviewer_allotment_id SET DEFAULT nextval('public.student_reviewer_allotments_student_reviewer_allotment_id_seq'::regclass);


--
-- Name: student_scholarships student_scholarship_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_scholarships ALTER COLUMN student_scholarship_id SET DEFAULT nextval('public.student_scholarships_student_scholarship_id_seq'::regclass);


--
-- Name: student_section_history history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_section_history ALTER COLUMN history_id SET DEFAULT nextval('public.student_section_history_history_id_seq'::regclass);


--
-- Name: student_status_history student_status_history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_status_history ALTER COLUMN student_status_history_id SET DEFAULT nextval('public.student_status_history_student_status_history_id_seq'::regclass);


--
-- Name: student_statuses student_status_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses ALTER COLUMN student_status_id SET DEFAULT nextval('public.student_statuses_student_status_id_seq'::regclass);


--
-- Name: student_transport_allocations student_transport_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations ALTER COLUMN student_transport_id SET DEFAULT nextval('public.student_transport_allocations_student_transport_id_seq'::regclass);


--
-- Name: students student_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students ALTER COLUMN student_id SET DEFAULT nextval('public.students_student_id_seq'::regclass);


--
-- Name: subject_components subject_component_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_components ALTER COLUMN subject_component_id SET DEFAULT nextval('public.subject_components_subject_component_id_seq'::regclass);


--
-- Name: subject_masters subject_master_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_masters ALTER COLUMN subject_master_id SET DEFAULT nextval('public.subject_masters_subject_master_id_seq'::regclass);


--
-- Name: subject_teacher_allocations subject_teacher_allocation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations ALTER COLUMN subject_teacher_allocation_id SET DEFAULT nextval('public.subject_teacher_allocations_subject_teacher_allocation_id_seq'::regclass);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations ALTER COLUMN substitute_teacher_allocation_id SET DEFAULT nextval('public.substitute_teacher_allocation_substitute_teacher_allocation_seq'::regclass);


--
-- Name: system_menus menu_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_menus ALTER COLUMN menu_id SET DEFAULT nextval('public.system_menus_menu_id_seq'::regclass);


--
-- Name: system_modules module_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_modules ALTER COLUMN module_id SET DEFAULT nextval('public.system_modules_module_id_seq'::regclass);


--
-- Name: system_settings setting_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings ALTER COLUMN setting_id SET DEFAULT nextval('public.system_settings_setting_id_seq'::regclass);


--
-- Name: time_slots time_slot_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_slots ALTER COLUMN time_slot_id SET DEFAULT nextval('public.time_slots_time_slot_id_seq'::regclass);


--
-- Name: timetable_entries timetable_entry_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_entries ALTER COLUMN timetable_entry_id SET DEFAULT nextval('public.timetable_entries_timetable_entry_id_seq'::regclass);


--
-- Name: transport_routes route_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_routes ALTER COLUMN route_id SET DEFAULT nextval('public.transport_routes_route_id_seq'::regclass);


--
-- Name: transport_stops stop_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_stops ALTER COLUMN stop_id SET DEFAULT nextval('public.transport_stops_stop_id_seq'::regclass);


--
-- Name: user_accounts user_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts ALTER COLUMN user_id SET DEFAULT nextval('public.user_accounts_user_id_seq'::regclass);


--
-- Name: user_permissions user_permission_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions ALTER COLUMN user_permission_id SET DEFAULT nextval('public.user_permissions_user_permission_id_seq'::regclass);


--
-- Name: user_photos user_photo_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_photos ALTER COLUMN user_photo_id SET DEFAULT nextval('public.user_photos_user_photo_id_seq'::regclass);


--
-- Name: user_status_history user_status_history_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_status_history ALTER COLUMN user_status_history_id SET DEFAULT nextval('public.user_status_history_user_status_history_id_seq'::regclass);


--
-- Name: user_types user_type_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_types ALTER COLUMN user_type_id SET DEFAULT nextval('public.user_types_user_type_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Name: vehicles vehicle_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles ALTER COLUMN vehicle_id SET DEFAULT nextval('public.vehicles_vehicle_id_seq'::regclass);


--
-- Name: user_logins user_logins_login_id_key; Type: CONSTRAINT; Schema: ABDC_DB; Owner: -
--

ALTER TABLE ONLY "ABDC_DB".user_logins
    ADD CONSTRAINT user_logins_login_id_key UNIQUE (login_id);


--
-- Name: user_logins user_logins_pkey; Type: CONSTRAINT; Schema: ABDC_DB; Owner: -
--

ALTER TABLE ONLY "ABDC_DB".user_logins
    ADD CONSTRAINT user_logins_pkey PRIMARY KEY (user_id);


--
-- Name: academic_breaks academic_breaks_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_breaks
    ADD CONSTRAINT academic_breaks_pkey PRIMARY KEY (academic_break_id);


--
-- Name: academic_breaks academic_breaks_time_configuration_id_start_time_end_time_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_breaks
    ADD CONSTRAINT academic_breaks_time_configuration_id_start_time_end_time_key UNIQUE (time_configuration_id, start_time, end_time);


--
-- Name: academic_periods academic_periods_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_periods
    ADD CONSTRAINT academic_periods_pkey PRIMARY KEY (period_id);


--
-- Name: academic_periods academic_periods_time_configuration_id_period_code_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_periods
    ADD CONSTRAINT academic_periods_time_configuration_id_period_code_key UNIQUE (time_configuration_id, period_code);


--
-- Name: academic_periods academic_periods_time_configuration_id_start_time_end_time_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_periods
    ADD CONSTRAINT academic_periods_time_configuration_id_start_time_end_time_key UNIQUE (time_configuration_id, start_time, end_time);


--
-- Name: academic_time_configuration_days academic_time_configuration_days_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configuration_days
    ADD CONSTRAINT academic_time_configuration_days_pkey PRIMARY KEY (time_configuration_id, week_day_id);


--
-- Name: academic_time_configurations academic_time_configurations_academic_year_id_configuration_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configurations
    ADD CONSTRAINT academic_time_configurations_academic_year_id_configuration_key UNIQUE (academic_year_id, configuration_name);


--
-- Name: academic_time_configurations academic_time_configurations_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configurations
    ADD CONSTRAINT academic_time_configurations_pkey PRIMARY KEY (time_configuration_id);


--
-- Name: attendance_calendar_dates attendance_calendar_dates_attendance_calendar_setting_id_at_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_dates
    ADD CONSTRAINT attendance_calendar_dates_attendance_calendar_setting_id_at_key UNIQUE (attendance_calendar_setting_id, attendance_date);


--
-- Name: attendance_calendar_dates attendance_calendar_dates_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_dates
    ADD CONSTRAINT attendance_calendar_dates_pkey PRIMARY KEY (attendance_calendar_date_id);


--
-- Name: attendance_calendar_settings attendance_calendar_settings_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_pkey PRIMARY KEY (attendance_calendar_setting_id);


--
-- Name: attendance_calendar_weekdays attendance_calendar_weekdays_attendance_calendar_setting_id_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_weekdays
    ADD CONSTRAINT attendance_calendar_weekdays_attendance_calendar_setting_id_key UNIQUE (attendance_calendar_setting_id, day_of_week);


--
-- Name: attendance_calendar_weekdays attendance_calendar_weekdays_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_weekdays
    ADD CONSTRAINT attendance_calendar_weekdays_pkey PRIMARY KEY (attendance_calendar_weekday_id);


--
-- Name: course_outcome_codes course_outcome_codes_co_code_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcome_codes
    ADD CONSTRAINT course_outcome_codes_co_code_key UNIQUE (co_code);


--
-- Name: course_outcome_codes course_outcome_codes_co_number_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcome_codes
    ADD CONSTRAINT course_outcome_codes_co_number_key UNIQUE (co_number);


--
-- Name: course_outcome_codes course_outcome_codes_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcome_codes
    ADD CONSTRAINT course_outcome_codes_pkey PRIMARY KEY (co_code_id);


--
-- Name: course_outcomes course_outcomes_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_pkey PRIMARY KEY (course_outcome_id);


--
-- Name: course_outcomes course_outcomes_subject_master_id_co_code_id_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_subject_master_id_co_code_id_key UNIQUE (subject_master_id, co_code_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_academic_year_id_programme_batc_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_academic_year_id_programme_batc_key UNIQUE (academic_year_id, programme_batch_id, semester_id, programme_section_id, subject_id, faculty_employee_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_pkey PRIMARY KEY (faculty_subject_assignment_id);


--
-- Name: lecture_notes lecture_notes_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lecture_notes
    ADD CONSTRAINT lecture_notes_pkey PRIMARY KEY (lecture_note_id);


--
-- Name: lesson_plan_books lesson_plan_books_lesson_plan_id_book_sequence_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_books
    ADD CONSTRAINT lesson_plan_books_lesson_plan_id_book_sequence_key UNIQUE (lesson_plan_id, book_sequence);


--
-- Name: lesson_plan_books lesson_plan_books_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_books
    ADD CONSTRAINT lesson_plan_books_pkey PRIMARY KEY (lesson_plan_book_id);


--
-- Name: lesson_plan_headers lesson_plan_headers_faculty_subject_assignment_id_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers
    ADD CONSTRAINT lesson_plan_headers_faculty_subject_assignment_id_key UNIQUE (faculty_subject_assignment_id);


--
-- Name: lesson_plan_headers lesson_plan_headers_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers
    ADD CONSTRAINT lesson_plan_headers_pkey PRIMARY KEY (lesson_plan_id);


--
-- Name: lesson_plan_topic_outcomes lesson_plan_topic_outcomes_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topic_outcomes
    ADD CONSTRAINT lesson_plan_topic_outcomes_pkey PRIMARY KEY (lesson_plan_topic_id, course_outcome_id);


--
-- Name: lesson_plan_topics lesson_plan_topics_lesson_plan_id_lesson_number_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_lesson_plan_id_lesson_number_key UNIQUE (lesson_plan_id, lesson_number);


--
-- Name: lesson_plan_topics lesson_plan_topics_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_pkey PRIMARY KEY (lesson_plan_topic_id);


--
-- Name: timetable_change_logs timetable_change_logs_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_change_logs
    ADD CONSTRAINT timetable_change_logs_pkey PRIMARY KEY (timetable_change_log_id);


--
-- Name: timetable_entries timetable_entries_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_pkey PRIMARY KEY (timetable_entry_id);


--
-- Name: timetable_entries timetable_entries_timetable_id_week_day_id_period_id_group__key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_timetable_id_week_day_id_period_id_group__key UNIQUE (timetable_id, week_day_id, period_id, group_id);


--
-- Name: timetable_headers timetable_headers_academic_year_id_programme_batch_id_semes_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_academic_year_id_programme_batch_id_semes_key UNIQUE (academic_year_id, programme_batch_id, semester_id, programme_section_id, group_id, version_number);


--
-- Name: timetable_headers timetable_headers_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_pkey PRIMARY KEY (timetable_id);


--
-- Name: timetable_working_days timetable_working_days_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_working_days
    ADD CONSTRAINT timetable_working_days_pkey PRIMARY KEY (timetable_working_day_id);


--
-- Name: timetable_working_days timetable_working_days_timetable_id_week_day_id_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_working_days
    ADD CONSTRAINT timetable_working_days_timetable_id_week_day_id_key UNIQUE (timetable_id, week_day_id);


--
-- Name: week_days week_days_day_code_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.week_days
    ADD CONSTRAINT week_days_day_code_key UNIQUE (day_code);


--
-- Name: week_days week_days_day_name_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.week_days
    ADD CONSTRAINT week_days_day_name_key UNIQUE (day_name);


--
-- Name: week_days week_days_day_number_key; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.week_days
    ADD CONSTRAINT week_days_day_number_key UNIQUE (day_number);


--
-- Name: week_days week_days_pkey; Type: CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.week_days
    ADD CONSTRAINT week_days_pkey PRIMARY KEY (week_day_id);


--
-- Name: sms_batches sms_batches_batch_reference_key; Type: CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_batches
    ADD CONSTRAINT sms_batches_batch_reference_key UNIQUE (batch_reference);


--
-- Name: sms_batches sms_batches_pkey; Type: CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_batches
    ADD CONSTRAINT sms_batches_pkey PRIMARY KEY (sms_batch_id);


--
-- Name: sms_recipients sms_recipients_pkey; Type: CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_recipients
    ADD CONSTRAINT sms_recipients_pkey PRIMARY KEY (sms_recipient_id);


--
-- Name: sms_templates sms_templates_pkey; Type: CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_templates
    ADD CONSTRAINT sms_templates_pkey PRIMARY KEY (sms_template_id);


--
-- Name: sms_templates sms_templates_template_code_key; Type: CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_templates
    ADD CONSTRAINT sms_templates_template_code_key UNIQUE (template_code);


--
-- Name: communication_modes communication_modes_mode_code_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.communication_modes
    ADD CONSTRAINT communication_modes_mode_code_key UNIQUE (mode_code);


--
-- Name: communication_modes communication_modes_mode_name_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.communication_modes
    ADD CONSTRAINT communication_modes_mode_name_key UNIQUE (mode_name);


--
-- Name: communication_modes communication_modes_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.communication_modes
    ADD CONSTRAINT communication_modes_pkey PRIMARY KEY (communication_mode_id);


--
-- Name: counselling_followups counselling_followups_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_followups
    ADD CONSTRAINT counselling_followups_pkey PRIMARY KEY (counselling_followup_id);


--
-- Name: counselling_purposes counselling_purposes_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_purposes
    ADD CONSTRAINT counselling_purposes_pkey PRIMARY KEY (counselling_purpose_id);


--
-- Name: counselling_purposes counselling_purposes_purpose_code_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_purposes
    ADD CONSTRAINT counselling_purposes_purpose_code_key UNIQUE (purpose_code);


--
-- Name: counselling_purposes counselling_purposes_purpose_name_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_purposes
    ADD CONSTRAINT counselling_purposes_purpose_name_key UNIQUE (purpose_name);


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remarks_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks
    ADD CONSTRAINT counselling_reviewer_remarks_pkey PRIMARY KEY (counselling_reviewer_remark_id);


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remarks_student_counselling_id_reviewe_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks
    ADD CONSTRAINT counselling_reviewer_remarks_student_counselling_id_reviewe_key UNIQUE (student_counselling_id, reviewer_level);


--
-- Name: employee_mentor_eligibility employee_mentor_eligibility_employee_id_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility
    ADD CONSTRAINT employee_mentor_eligibility_employee_id_key UNIQUE (employee_id);


--
-- Name: employee_mentor_eligibility_history employee_mentor_eligibility_history_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility_history
    ADD CONSTRAINT employee_mentor_eligibility_history_pkey PRIMARY KEY (employee_mentor_eligibility_history_id);


--
-- Name: employee_mentor_eligibility employee_mentor_eligibility_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility
    ADD CONSTRAINT employee_mentor_eligibility_pkey PRIMARY KEY (employee_mentor_eligibility_id);


--
-- Name: first_reviewer_remarks first_reviewer_remarks_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_pkey PRIMARY KEY (first_reviewer_remark_id);


--
-- Name: mentor_assignment_changes mentor_assignment_changes_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes
    ADD CONSTRAINT mentor_assignment_changes_pkey PRIMARY KEY (assignment_change_id);


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_allotment_det_mentor_reviewer_allotment_id__key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details
    ADD CONSTRAINT mentor_reviewer_allotment_det_mentor_reviewer_allotment_id__key UNIQUE (mentor_reviewer_allotment_id, reviewer_role);


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_key1; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details
    ADD CONSTRAINT mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_key1 UNIQUE (mentor_reviewer_allotment_id, reviewer_id);


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_allotment_details_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details
    ADD CONSTRAINT mentor_reviewer_allotment_details_pkey PRIMARY KEY (mentor_reviewer_detail_id);


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotments_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments
    ADD CONSTRAINT mentor_reviewer_allotments_pkey PRIMARY KEY (mentor_reviewer_allotment_id);


--
-- Name: mentor_reviewer_change_history mentor_reviewer_change_history_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_change_history
    ADD CONSTRAINT mentor_reviewer_change_history_pkey PRIMARY KEY (mentor_reviewer_change_id);


--
-- Name: mentors mentors_employee_id_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT mentors_employee_id_key UNIQUE (employee_id);


--
-- Name: mentors mentors_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT mentors_pkey PRIMARY KEY (mentor_id);


--
-- Name: parent_interactions parent_interactions_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions
    ADD CONSTRAINT parent_interactions_pkey PRIMARY KEY (parent_interaction_id);


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_pkey PRIMARY KEY (prospective_student_mentor_allotment_id);


--
-- Name: reviewers reviewers_employee_id_key; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.reviewers
    ADD CONSTRAINT reviewers_employee_id_key UNIQUE (employee_id);


--
-- Name: reviewers reviewers_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.reviewers
    ADD CONSTRAINT reviewers_pkey PRIMARY KEY (reviewer_id);


--
-- Name: student_counsellings student_counsellings_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_pkey PRIMARY KEY (student_counselling_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_pkey; Type: CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_pkey PRIMARY KEY (mentor_allotment_id);


--
-- Name: permission_change_history permission_change_history_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history
    ADD CONSTRAINT permission_change_history_pkey PRIMARY KEY (history_id);


--
-- Name: permissions permissions_permission_code_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permissions
    ADD CONSTRAINT permissions_permission_code_key UNIQUE (permission_code);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (permission_id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_permission_id);


--
-- Name: role_permissions role_permissions_role_id_menu_id_permission_id_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.role_permissions
    ADD CONSTRAINT role_permissions_role_id_menu_id_permission_id_key UNIQUE (role_id, menu_id, permission_id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: roles roles_role_code_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.roles
    ADD CONSTRAINT roles_role_code_key UNIQUE (role_code);


--
-- Name: system_menus system_menus_menu_code_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_menus
    ADD CONSTRAINT system_menus_menu_code_key UNIQUE (menu_code);


--
-- Name: system_menus system_menus_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_menus
    ADD CONSTRAINT system_menus_pkey PRIMARY KEY (menu_id);


--
-- Name: system_modules system_modules_module_code_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_modules
    ADD CONSTRAINT system_modules_module_code_key UNIQUE (module_code);


--
-- Name: system_modules system_modules_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_modules
    ADD CONSTRAINT system_modules_pkey PRIMARY KEY (module_id);


--
-- Name: user_permissions user_permissions_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions
    ADD CONSTRAINT user_permissions_pkey PRIMARY KEY (user_permission_id);


--
-- Name: user_permissions user_permissions_user_id_menu_id_permission_id_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions
    ADD CONSTRAINT user_permissions_user_id_menu_id_permission_id_key UNIQUE (user_id, menu_id, permission_id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_role_id);


--
-- Name: user_roles user_roles_user_id_role_id_department_id_key; Type: CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_roles
    ADD CONSTRAINT user_roles_user_id_role_id_department_id_key UNIQUE (user_id, role_id, department_id);


--
-- Name: academic_terms academic_terms_academic_year_id_term_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_terms
    ADD CONSTRAINT academic_terms_academic_year_id_term_name_key UNIQUE (academic_year_id, term_name);


--
-- Name: academic_terms academic_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_terms
    ADD CONSTRAINT academic_terms_pkey PRIMARY KEY (term_id);


--
-- Name: academic_years academic_years_institution_id_year_label_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years
    ADD CONSTRAINT academic_years_institution_id_year_label_key UNIQUE (institution_id, year_label);


--
-- Name: academic_years academic_years_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years
    ADD CONSTRAINT academic_years_pkey PRIMARY KEY (academic_year_id);


--
-- Name: admission_batches admission_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_batches
    ADD CONSTRAINT admission_batches_pkey PRIMARY KEY (batch_id);


--
-- Name: admission_batches admission_batches_programme_id_admission_year_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_batches
    ADD CONSTRAINT admission_batches_programme_id_admission_year_key UNIQUE (programme_id, admission_year);


--
-- Name: admission_categories admission_categories_institute_id_category_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories
    ADD CONSTRAINT admission_categories_institute_id_category_code_key UNIQUE (institute_id, category_code);


--
-- Name: admission_categories admission_categories_institute_id_category_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories
    ADD CONSTRAINT admission_categories_institute_id_category_name_key UNIQUE (institute_id, category_name);


--
-- Name: admission_categories admission_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories
    ADD CONSTRAINT admission_categories_pkey PRIMARY KEY (admission_category_id);


--
-- Name: approval_actions approval_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_actions
    ADD CONSTRAINT approval_actions_pkey PRIMARY KEY (approval_action_id);


--
-- Name: approval_requests approval_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_pkey PRIMARY KEY (approval_request_id);


--
-- Name: assessment_components assessment_components_offering_id_examination_id_component__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_components
    ADD CONSTRAINT assessment_components_offering_id_examination_id_component__key UNIQUE (offering_id, examination_id, component_name);


--
-- Name: assessment_components assessment_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_components
    ADD CONSTRAINT assessment_components_pkey PRIMARY KEY (assessment_id);


--
-- Name: attendance_sessions attendance_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_sessions
    ADD CONSTRAINT attendance_sessions_pkey PRIMARY KEY (attendance_session_id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (audit_log_id);


--
-- Name: batch_section_assignments batch_section_assignments_batch_id_section_master_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_section_assignments
    ADD CONSTRAINT batch_section_assignments_batch_id_section_master_id_key UNIQUE (batch_id, section_master_id);


--
-- Name: batch_section_assignments batch_section_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_section_assignments
    ADD CONSTRAINT batch_section_assignments_pkey PRIMARY KEY (assignment_id);


--
-- Name: batch_survey_settings batch_survey_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_survey_settings
    ADD CONSTRAINT batch_survey_settings_pkey PRIMARY KEY (batch_id);


--
-- Name: building_departments building_departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.building_departments
    ADD CONSTRAINT building_departments_pkey PRIMARY KEY (building_id, department_id);


--
-- Name: buildings buildings_campus_id_building_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings
    ADD CONSTRAINT buildings_campus_id_building_code_key UNIQUE (campus_id, building_code);


--
-- Name: buildings buildings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings
    ADD CONSTRAINT buildings_pkey PRIMARY KEY (building_id);


--
-- Name: campuses campuses_institution_id_campus_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campuses
    ADD CONSTRAINT campuses_institution_id_campus_code_key UNIQUE (institution_id, campus_code);


--
-- Name: campuses campuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campuses
    ADD CONSTRAINT campuses_pkey PRIMARY KEY (campus_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_pkey PRIMARY KEY (class_teacher_allocation_id);


--
-- Name: classroom_facilities classroom_facilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facilities
    ADD CONSTRAINT classroom_facilities_pkey PRIMARY KEY (classroom_id, facility_id);


--
-- Name: classroom_facility_masters classroom_facility_masters_facility_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facility_masters
    ADD CONSTRAINT classroom_facility_masters_facility_code_key UNIQUE (facility_code);


--
-- Name: classroom_facility_masters classroom_facility_masters_facility_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facility_masters
    ADD CONSTRAINT classroom_facility_masters_facility_name_key UNIQUE (facility_name);


--
-- Name: classroom_facility_masters classroom_facility_masters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facility_masters
    ADD CONSTRAINT classroom_facility_masters_pkey PRIMARY KEY (facility_id);


--
-- Name: classroom_types classroom_types_classroom_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_types
    ADD CONSTRAINT classroom_types_classroom_type_code_key UNIQUE (classroom_type_code);


--
-- Name: classroom_types classroom_types_classroom_type_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_types
    ADD CONSTRAINT classroom_types_classroom_type_name_key UNIQUE (classroom_type_name);


--
-- Name: classroom_types classroom_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_types
    ADD CONSTRAINT classroom_types_pkey PRIMARY KEY (classroom_type_id);


--
-- Name: classroom_unavailability classroom_unavailability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_unavailability
    ADD CONSTRAINT classroom_unavailability_pkey PRIMARY KEY (classroom_unavailability_id);


--
-- Name: classrooms classrooms_building_id_room_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_building_id_room_no_key UNIQUE (building_id, room_no);


--
-- Name: classrooms classrooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_pkey PRIMARY KEY (classroom_id);


--
-- Name: common_master_types common_master_types_institute_id_master_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_types
    ADD CONSTRAINT common_master_types_institute_id_master_type_code_key UNIQUE (institute_id, master_type_code);


--
-- Name: common_master_types common_master_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_types
    ADD CONSTRAINT common_master_types_pkey PRIMARY KEY (master_type_id);


--
-- Name: common_master_values common_master_values_master_type_id_value_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values
    ADD CONSTRAINT common_master_values_master_type_id_value_code_key UNIQUE (master_type_id, value_code);


--
-- Name: common_master_values common_master_values_master_type_id_value_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values
    ADD CONSTRAINT common_master_values_master_type_id_value_name_key UNIQUE (master_type_id, value_name);


--
-- Name: common_master_values common_master_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values
    ADD CONSTRAINT common_master_values_pkey PRIMARY KEY (master_value_id);


--
-- Name: course_initial_setup course_initial_setup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_initial_setup
    ADD CONSTRAINT course_initial_setup_pkey PRIMARY KEY (course_id);


--
-- Name: course_offerings course_offerings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_offerings
    ADD CONSTRAINT course_offerings_pkey PRIMARY KEY (offering_id);


--
-- Name: course_offerings course_offerings_term_id_curriculum_course_id_section_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_offerings
    ADD CONSTRAINT course_offerings_term_id_curriculum_course_id_section_id_key UNIQUE (term_id, curriculum_course_id, section_id);


--
-- Name: course_prerequisites course_prerequisites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_prerequisites
    ADD CONSTRAINT course_prerequisites_pkey PRIMARY KEY (course_id, prerequisite_course_id);


--
-- Name: course_results course_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_results
    ADD CONSTRAINT course_results_pkey PRIMARY KEY (course_result_id);


--
-- Name: course_results course_results_student_id_offering_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_results
    ADD CONSTRAINT course_results_student_id_offering_id_key UNIQUE (student_id, offering_id);


--
-- Name: courses courses_department_id_course_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_department_id_course_code_key UNIQUE (department_id, course_code);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (course_id);


--
-- Name: curriculum_courses curriculum_courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_courses
    ADD CONSTRAINT curriculum_courses_pkey PRIMARY KEY (curriculum_course_id);


--
-- Name: curriculum_courses curriculum_courses_scheme_id_semester_id_course_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_courses
    ADD CONSTRAINT curriculum_courses_scheme_id_semester_id_course_id_key UNIQUE (scheme_id, semester_id, course_id);


--
-- Name: curriculum_schemes curriculum_schemes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_schemes
    ADD CONSTRAINT curriculum_schemes_pkey PRIMARY KEY (scheme_id);


--
-- Name: curriculum_schemes curriculum_schemes_programme_id_scheme_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_schemes
    ADD CONSTRAINT curriculum_schemes_programme_id_scheme_name_key UNIQUE (programme_id, scheme_name);


--
-- Name: dashboard_messages dashboard_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_messages
    ADD CONSTRAINT dashboard_messages_pkey PRIMARY KEY (dashboard_message_id);


--
-- Name: dashboard_notice_acknowledgments dashboard_notice_acknowledgments_notice_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_acknowledgments
    ADD CONSTRAINT dashboard_notice_acknowledgments_notice_id_user_id_key UNIQUE (notice_id, user_id);


--
-- Name: dashboard_notice_acknowledgments dashboard_notice_acknowledgments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_acknowledgments
    ADD CONSTRAINT dashboard_notice_acknowledgments_pkey PRIMARY KEY (notice_acknowledgment_id);


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_pkey PRIMARY KEY (notice_audience_id);


--
-- Name: dashboard_notices dashboard_notices_notice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_notice_number_key UNIQUE (notice_number);


--
-- Name: dashboard_notices dashboard_notices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_pkey PRIMARY KEY (notice_id);


--
-- Name: departments departments_institution_id_department_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_institution_id_department_code_key UNIQUE (institution_id, department_code);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (department_id);


--
-- Name: designations designations_designation_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designations
    ADD CONSTRAINT designations_designation_code_key UNIQUE (designation_code);


--
-- Name: designations designations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designations
    ADD CONSTRAINT designations_pkey PRIMARY KEY (designation_id);


--
-- Name: document_types document_types_document_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_types
    ADD CONSTRAINT document_types_document_type_code_key UNIQUE (document_type_code);


--
-- Name: document_types document_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_types
    ADD CONSTRAINT document_types_pkey PRIMARY KEY (document_type_id);


--
-- Name: employee_leaves employee_leaves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leaves
    ADD CONSTRAINT employee_leaves_pkey PRIMARY KEY (leave_id);


--
-- Name: employee_login_history employee_login_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_login_history
    ADD CONSTRAINT employee_login_history_pkey PRIMARY KEY (history_id);


--
-- Name: employee_qualifications employee_qualifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_qualifications
    ADD CONSTRAINT employee_qualifications_pkey PRIMARY KEY (qualification_id);


--
-- Name: employees employees_institution_id_employee_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_institution_id_employee_code_key UNIQUE (institution_id, employee_code);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (employee_id);


--
-- Name: employees employees_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_user_id_key UNIQUE (user_id);


--
-- Name: exam_types exam_types_institution_id_exam_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types
    ADD CONSTRAINT exam_types_institution_id_exam_type_code_key UNIQUE (institution_id, exam_type_code);


--
-- Name: exam_types exam_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types
    ADD CONSTRAINT exam_types_pkey PRIMARY KEY (exam_type_id);


--
-- Name: examinations examinations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.examinations
    ADD CONSTRAINT examinations_pkey PRIMARY KEY (examination_id);


--
-- Name: faculty_course_allocations faculty_course_allocations_offering_id_employee_id_allocati_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faculty_course_allocations
    ADD CONSTRAINT faculty_course_allocations_offering_id_employee_id_allocati_key UNIQUE (offering_id, employee_id, allocation_role);


--
-- Name: faculty_course_allocations faculty_course_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faculty_course_allocations
    ADD CONSTRAINT faculty_course_allocations_pkey PRIMARY KEY (allocation_id);


--
-- Name: fee_heads fee_heads_institution_id_fee_head_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_heads
    ADD CONSTRAINT fee_heads_institution_id_fee_head_code_key UNIQUE (institution_id, fee_head_code);


--
-- Name: fee_heads fee_heads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_heads
    ADD CONSTRAINT fee_heads_pkey PRIMARY KEY (fee_head_id);


--
-- Name: fee_payment_allocations fee_payment_allocations_payment_id_demand_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payment_allocations
    ADD CONSTRAINT fee_payment_allocations_payment_id_demand_id_key UNIQUE (payment_id, demand_id);


--
-- Name: fee_payment_allocations fee_payment_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payment_allocations
    ADD CONSTRAINT fee_payment_allocations_pkey PRIMARY KEY (payment_allocation_id);


--
-- Name: fee_payments fee_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payments
    ADD CONSTRAINT fee_payments_pkey PRIMARY KEY (payment_id);


--
-- Name: fee_payments fee_payments_receipt_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payments
    ADD CONSTRAINT fee_payments_receipt_number_key UNIQUE (receipt_number);


--
-- Name: fee_structure_items fee_structure_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structure_items
    ADD CONSTRAINT fee_structure_items_pkey PRIMARY KEY (fee_structure_item_id);


--
-- Name: fee_structures fee_structures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structures
    ADD CONSTRAINT fee_structures_pkey PRIMARY KEY (fee_structure_id);


--
-- Name: file_attachments file_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file_attachments
    ADD CONSTRAINT file_attachments_pkey PRIMARY KEY (attachment_id);


--
-- Name: grade_scales grade_scales_institution_id_grade_letter_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales
    ADD CONSTRAINT grade_scales_institution_id_grade_letter_key UNIQUE (institution_id, grade_letter);


--
-- Name: grade_scales grade_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales
    ADD CONSTRAINT grade_scales_pkey PRIMARY KEY (grade_scale_id);


--
-- Name: grievance_actions grievance_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievance_actions
    ADD CONSTRAINT grievance_actions_pkey PRIMARY KEY (grievance_action_id);


--
-- Name: grievances grievances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievances
    ADD CONSTRAINT grievances_pkey PRIMARY KEY (grievance_id);


--
-- Name: guardians guardians_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardians
    ADD CONSTRAINT guardians_pkey PRIMARY KEY (guardian_id);


--
-- Name: hostel_allocations hostel_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_allocations
    ADD CONSTRAINT hostel_allocations_pkey PRIMARY KEY (hostel_allocation_id);


--
-- Name: hostel_rooms hostel_rooms_hostel_id_room_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_rooms
    ADD CONSTRAINT hostel_rooms_hostel_id_room_number_key UNIQUE (hostel_id, room_number);


--
-- Name: hostel_rooms hostel_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_rooms
    ADD CONSTRAINT hostel_rooms_pkey PRIMARY KEY (hostel_room_id);


--
-- Name: hostels hostels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostels
    ADD CONSTRAINT hostels_pkey PRIMARY KEY (hostel_id);


--
-- Name: institutions institutions_institution_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.institutions
    ADD CONSTRAINT institutions_institution_code_key UNIQUE (institution_code);


--
-- Name: institutions institutions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.institutions
    ADD CONSTRAINT institutions_pkey PRIMARY KEY (institution_id);


--
-- Name: issue_followups issue_followups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_followups
    ADD CONSTRAINT issue_followups_pkey PRIMARY KEY (followup_id);


--
-- Name: libraries libraries_institution_id_library_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.libraries
    ADD CONSTRAINT libraries_institution_id_library_code_key UNIQUE (institution_id, library_code);


--
-- Name: libraries libraries_institution_id_library_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.libraries
    ADD CONSTRAINT libraries_institution_id_library_name_key UNIQUE (institution_id, library_name);


--
-- Name: libraries libraries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.libraries
    ADD CONSTRAINT libraries_pkey PRIMARY KEY (library_id);


--
-- Name: library_almiras library_almiras_library_id_almira_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_almiras
    ADD CONSTRAINT library_almiras_library_id_almira_code_key UNIQUE (library_id, almira_code);


--
-- Name: library_almiras library_almiras_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_almiras
    ADD CONSTRAINT library_almiras_pkey PRIMARY KEY (almira_id);


--
-- Name: library_authors library_authors_author_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_authors
    ADD CONSTRAINT library_authors_author_name_key UNIQUE (author_name);


--
-- Name: library_authors library_authors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_authors
    ADD CONSTRAINT library_authors_pkey PRIMARY KEY (author_id);


--
-- Name: library_book_copies library_book_copies_accession_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_copies
    ADD CONSTRAINT library_book_copies_accession_number_key UNIQUE (accession_number);


--
-- Name: library_book_copies library_book_copies_barcode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_copies
    ADD CONSTRAINT library_book_copies_barcode_key UNIQUE (barcode);


--
-- Name: library_book_copies library_book_copies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_copies
    ADD CONSTRAINT library_book_copies_pkey PRIMARY KEY (book_copy_id);


--
-- Name: library_book_issues library_book_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_issues
    ADD CONSTRAINT library_book_issues_pkey PRIMARY KEY (book_issue_id);


--
-- Name: library_book_stock library_book_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_stock
    ADD CONSTRAINT library_book_stock_pkey PRIMARY KEY (book_id);


--
-- Name: library_books library_books_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_pkey PRIMARY KEY (book_id);


--
-- Name: library_categories library_categories_category_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories
    ADD CONSTRAINT library_categories_category_code_key UNIQUE (category_code);


--
-- Name: library_categories library_categories_category_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories
    ADD CONSTRAINT library_categories_category_name_key UNIQUE (category_name);


--
-- Name: library_categories library_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories
    ADD CONSTRAINT library_categories_pkey PRIMARY KEY (category_id);


--
-- Name: library_issue_types library_issue_types_issue_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_issue_types
    ADD CONSTRAINT library_issue_types_issue_type_code_key UNIQUE (issue_type_code);


--
-- Name: library_issue_types library_issue_types_issue_type_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_issue_types
    ADD CONSTRAINT library_issue_types_issue_type_name_key UNIQUE (issue_type_name);


--
-- Name: library_issue_types library_issue_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_issue_types
    ADD CONSTRAINT library_issue_types_pkey PRIMARY KEY (issue_type_id);


--
-- Name: library_members library_members_membership_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_members
    ADD CONSTRAINT library_members_membership_number_key UNIQUE (membership_number);


--
-- Name: library_members library_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_members
    ADD CONSTRAINT library_members_pkey PRIMARY KEY (library_member_id);


--
-- Name: library_members library_members_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_members
    ADD CONSTRAINT library_members_user_id_key UNIQUE (user_id);


--
-- Name: library_publishers library_publishers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_publishers
    ADD CONSTRAINT library_publishers_pkey PRIMARY KEY (publisher_id);


--
-- Name: library_publishers library_publishers_publisher_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_publishers
    ADD CONSTRAINT library_publishers_publisher_code_key UNIQUE (publisher_code);


--
-- Name: library_publishers library_publishers_publisher_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_publishers
    ADD CONSTRAINT library_publishers_publisher_name_key UNIQUE (publisher_name);


--
-- Name: library_purchase_invoice_items library_purchase_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoice_items
    ADD CONSTRAINT library_purchase_invoice_items_pkey PRIMARY KEY (invoice_item_id);


--
-- Name: library_purchase_invoices library_purchase_invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices
    ADD CONSTRAINT library_purchase_invoices_invoice_number_key UNIQUE (invoice_number);


--
-- Name: library_purchase_invoices library_purchase_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices
    ADD CONSTRAINT library_purchase_invoices_pkey PRIMARY KEY (invoice_id);


--
-- Name: library_purchase_order_items library_purchase_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_order_items
    ADD CONSTRAINT library_purchase_order_items_pkey PRIMARY KEY (purchase_order_item_id);


--
-- Name: library_purchase_orders library_purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_orders
    ADD CONSTRAINT library_purchase_orders_pkey PRIMARY KEY (purchase_order_id);


--
-- Name: library_purchase_orders library_purchase_orders_po_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_orders
    ADD CONSTRAINT library_purchase_orders_po_number_key UNIQUE (po_number);


--
-- Name: library_student_members library_student_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_student_members
    ADD CONSTRAINT library_student_members_pkey PRIMARY KEY (student_member_id);


--
-- Name: library_student_members library_student_members_roll_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_student_members
    ADD CONSTRAINT library_student_members_roll_number_key UNIQUE (roll_number);


--
-- Name: library_study_material_issues library_study_material_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_issues
    ADD CONSTRAINT library_study_material_issues_pkey PRIMARY KEY (material_issue_id);


--
-- Name: library_study_material_prices library_study_material_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_prices
    ADD CONSTRAINT library_study_material_prices_pkey PRIMARY KEY (price_id);


--
-- Name: library_study_material_prices library_study_material_prices_study_material_id_effective_f_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_prices
    ADD CONSTRAINT library_study_material_prices_study_material_id_effective_f_key UNIQUE (study_material_id, effective_from);


--
-- Name: library_study_materials library_study_materials_material_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_material_code_key UNIQUE (material_code);


--
-- Name: library_study_materials library_study_materials_material_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_material_name_key UNIQUE (material_name);


--
-- Name: library_study_materials library_study_materials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_pkey PRIMARY KEY (study_material_id);


--
-- Name: library_subjects library_subjects_department_id_subject_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects
    ADD CONSTRAINT library_subjects_department_id_subject_name_key UNIQUE (department_id, subject_name);


--
-- Name: library_subjects library_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects
    ADD CONSTRAINT library_subjects_pkey PRIMARY KEY (subject_id);


--
-- Name: library_subjects library_subjects_subject_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects
    ADD CONSTRAINT library_subjects_subject_code_key UNIQUE (subject_code);


--
-- Name: library_suppliers library_suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_suppliers
    ADD CONSTRAINT library_suppliers_pkey PRIMARY KEY (supplier_id);


--
-- Name: library_suppliers library_suppliers_supplier_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_suppliers
    ADD CONSTRAINT library_suppliers_supplier_code_key UNIQUE (supplier_code);


--
-- Name: library_suppliers library_suppliers_supplier_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_suppliers
    ADD CONSTRAINT library_suppliers_supplier_name_key UNIQUE (supplier_name);


--
-- Name: library_titles library_titles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_titles
    ADD CONSTRAINT library_titles_pkey PRIMARY KEY (title_id);


--
-- Name: library_titles library_titles_title_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_titles
    ADD CONSTRAINT library_titles_title_code_key UNIQUE (title_code);


--
-- Name: library_titles library_titles_title_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_titles
    ADD CONSTRAINT library_titles_title_name_key UNIQUE (title_name);


--
-- Name: library_transactions library_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_transactions
    ADD CONSTRAINT library_transactions_pkey PRIMARY KEY (library_transaction_id);


--
-- Name: login_history login_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history
    ADD CONSTRAINT login_history_pkey PRIMARY KEY (login_history_id);


--
-- Name: login_logs login_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_logs
    ADD CONSTRAINT login_logs_pkey PRIMARY KEY (login_log_id);


--
-- Name: mentor_assignments mentor_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_assignments
    ADD CONSTRAINT mentor_assignments_pkey PRIMARY KEY (mentor_assignment_id);


--
-- Name: mentor_assignments mentor_assignments_student_id_academic_year_id_assigned_fro_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_assignments
    ADD CONSTRAINT mentor_assignments_student_id_academic_year_id_assigned_fro_key UNIQUE (student_id, academic_year_id, assigned_from);


--
-- Name: mentor_meetings mentor_meetings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_meetings
    ADD CONSTRAINT mentor_meetings_pkey PRIMARY KEY (mentor_meeting_id);


--
-- Name: mentoring_topics mentoring_topics_institute_id_topic_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentoring_topics
    ADD CONSTRAINT mentoring_topics_institute_id_topic_code_key UNIQUE (institute_id, topic_code);


--
-- Name: mentoring_topics mentoring_topics_institute_id_topic_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentoring_topics
    ADD CONSTRAINT mentoring_topics_institute_id_topic_name_key UNIQUE (institute_id, topic_name);


--
-- Name: mentoring_topics mentoring_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentoring_topics
    ADD CONSTRAINT mentoring_topics_pkey PRIMARY KEY (mentoring_topic_id);


--
-- Name: notices notices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_pkey PRIMARY KEY (notice_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (notification_id);


--
-- Name: password_reset_history password_reset_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_history
    ADD CONSTRAINT password_reset_history_pkey PRIMARY KEY (reset_id);


--
-- Name: permission_change_history permission_change_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history
    ADD CONSTRAINT permission_change_history_pkey PRIMARY KEY (history_id);


--
-- Name: permissions permissions_permission_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_permission_code_key UNIQUE (permission_code);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (permission_id);


--
-- Name: preferred_books preferred_books_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preferred_books
    ADD CONSTRAINT preferred_books_pkey PRIMARY KEY (preferred_book_id);


--
-- Name: preferred_books preferred_books_subject_master_id_book_title_edition_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preferred_books
    ADD CONSTRAINT preferred_books_subject_master_id_book_title_edition_key UNIQUE (subject_master_id, book_title, edition);


--
-- Name: programme_section_merges programme_section_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges
    ADD CONSTRAINT programme_section_merges_pkey PRIMARY KEY (merge_id);


--
-- Name: programme_semester_definitions programme_semester_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT programme_semester_definitions_pkey PRIMARY KEY (programme_semester_id);


--
-- Name: programmes programmes_department_id_programme_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programmes
    ADD CONSTRAINT programmes_department_id_programme_code_key UNIQUE (department_id, programme_code);


--
-- Name: programmes programmes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programmes
    ADD CONSTRAINT programmes_pkey PRIMARY KEY (programme_id);


--
-- Name: prospective_student_followups prospective_student_followups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_followups
    ADD CONSTRAINT prospective_student_followups_pkey PRIMARY KEY (prospective_student_followup_id);


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_pkey PRIMARY KEY (prospective_student_mentor_allotment_id);


--
-- Name: prospective_students prospective_students_institute_id_enquiry_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_institute_id_enquiry_number_key UNIQUE (institute_id, enquiry_number);


--
-- Name: prospective_students prospective_students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_pkey PRIMARY KEY (prospective_student_id);


--
-- Name: reviewer_allotment_mentors reviewer_allotment_mentors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviewer_allotment_mentors
    ADD CONSTRAINT reviewer_allotment_mentors_pkey PRIMARY KEY (student_reviewer_allotment_id, mentor_employee_id);


--
-- Name: reviewer_allotment_students reviewer_allotment_students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviewer_allotment_students
    ADD CONSTRAINT reviewer_allotment_students_pkey PRIMARY KEY (student_reviewer_allotment_id, student_id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: roles roles_role_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_role_code_key UNIQUE (role_code);


--
-- Name: rooms rooms_building_id_room_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_building_id_room_number_key UNIQUE (building_id, room_number);


--
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (room_id);


--
-- Name: route_vehicle_assignments route_vehicle_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_vehicle_assignments
    ADD CONSTRAINT route_vehicle_assignments_pkey PRIMARY KEY (assignment_id);


--
-- Name: scholarships scholarships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scholarships
    ADD CONSTRAINT scholarships_pkey PRIMARY KEY (scholarship_id);


--
-- Name: section_definitions section_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_definitions
    ADD CONSTRAINT section_definitions_pkey PRIMARY KEY (section_definition_id);


--
-- Name: section_masters section_masters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_masters
    ADD CONSTRAINT section_masters_pkey PRIMARY KEY (section_master_id);


--
-- Name: section_masters section_masters_section_master_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_masters
    ADD CONSTRAINT section_masters_section_master_code_key UNIQUE (section_master_code);


--
-- Name: section_masters section_masters_section_master_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_masters
    ADD CONSTRAINT section_masters_section_master_name_key UNIQUE (section_master_name);


--
-- Name: section_merge_groups section_merge_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_merge_groups
    ADD CONSTRAINT section_merge_groups_pkey PRIMARY KEY (merge_group_id);


--
-- Name: sections sections_batch_id_semester_id_term_id_section_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_batch_id_semester_id_term_id_section_name_key UNIQUE (batch_id, semester_id, term_id, section_name);


--
-- Name: sections sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_pkey PRIMARY KEY (section_id);


--
-- Name: semester_results semester_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semester_results
    ADD CONSTRAINT semester_results_pkey PRIMARY KEY (semester_result_id);


--
-- Name: semester_results semester_results_student_id_term_id_semester_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semester_results
    ADD CONSTRAINT semester_results_student_id_term_id_semester_id_key UNIQUE (student_id, term_id, semester_id);


--
-- Name: semesters semesters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_pkey PRIMARY KEY (semester_id);


--
-- Name: semesters semesters_programme_id_semester_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_programme_id_semester_number_key UNIQUE (programme_id, semester_number);


--
-- Name: student_academic_history student_academic_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_academic_history
    ADD CONSTRAINT student_academic_history_pkey PRIMARY KEY (history_id);


--
-- Name: student_addresses student_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_addresses
    ADD CONSTRAINT student_addresses_pkey PRIMARY KEY (student_address_id);


--
-- Name: student_addresses student_addresses_student_id_address_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_addresses
    ADD CONSTRAINT student_addresses_student_id_address_type_key UNIQUE (student_id, address_type);


--
-- Name: student_attendance student_attendance_attendance_session_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance
    ADD CONSTRAINT student_attendance_attendance_session_id_student_id_key UNIQUE (attendance_session_id, student_id);


--
-- Name: student_attendance_entries student_attendance_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entries
    ADD CONSTRAINT student_attendance_entries_pkey PRIMARY KEY (attendance_entry_id);


--
-- Name: student_attendance_entries student_attendance_entries_subject_teacher_allocation_id_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entries
    ADD CONSTRAINT student_attendance_entries_subject_teacher_allocation_id_at_key UNIQUE (subject_teacher_allocation_id, attendance_date, start_time);


--
-- Name: student_attendance_entry_students student_attendance_entry_students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entry_students
    ADD CONSTRAINT student_attendance_entry_students_pkey PRIMARY KEY (attendance_entry_id, student_id);


--
-- Name: student_attendance student_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance
    ADD CONSTRAINT student_attendance_pkey PRIMARY KEY (attendance_id);


--
-- Name: student_branches student_branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_branches
    ADD CONSTRAINT student_branches_pkey PRIMARY KEY (branch_id);


--
-- Name: student_branches student_branches_programme_id_branch_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_branches
    ADD CONSTRAINT student_branches_programme_id_branch_code_key UNIQUE (programme_id, branch_code);


--
-- Name: student_branches student_branches_programme_id_branch_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_branches
    ADD CONSTRAINT student_branches_programme_id_branch_name_key UNIQUE (programme_id, branch_name);


--
-- Name: student_course_registrations student_course_registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_course_registrations
    ADD CONSTRAINT student_course_registrations_pkey PRIMARY KEY (registration_id);


--
-- Name: student_course_registrations student_course_registrations_student_id_offering_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_course_registrations
    ADD CONSTRAINT student_course_registrations_student_id_offering_id_key UNIQUE (student_id, offering_id);


--
-- Name: student_documents student_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_pkey PRIMARY KEY (student_document_id);


--
-- Name: student_fee_demands student_fee_demands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_demands
    ADD CONSTRAINT student_fee_demands_pkey PRIMARY KEY (demand_id);


--
-- Name: student_fee_undertakings student_fee_undertakings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_pkey PRIMARY KEY (student_fee_undertaking_id);


--
-- Name: student_guardians student_guardians_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardians
    ADD CONSTRAINT student_guardians_pkey PRIMARY KEY (student_id, guardian_id);


--
-- Name: student_import_batches student_import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_import_batches
    ADD CONSTRAINT student_import_batches_pkey PRIMARY KEY (student_import_batch_id);


--
-- Name: student_issues student_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_issues
    ADD CONSTRAINT student_issues_pkey PRIMARY KEY (student_issue_id);


--
-- Name: student_login_actions student_login_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_login_actions
    ADD CONSTRAINT student_login_actions_pkey PRIMARY KEY (student_login_action_id);


--
-- Name: student_marks student_marks_assessment_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_assessment_id_student_id_key UNIQUE (assessment_id, student_id);


--
-- Name: student_marks student_marks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_pkey PRIMARY KEY (mark_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_pkey PRIMARY KEY (mentor_allotment_id);


--
-- Name: student_mentor_transfer_history student_mentor_transfer_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_transfer_history
    ADD CONSTRAINT student_mentor_transfer_history_pkey PRIMARY KEY (student_mentor_transfer_history_id);


--
-- Name: student_mentoring_attachments student_mentoring_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_attachments
    ADD CONSTRAINT student_mentoring_attachments_pkey PRIMARY KEY (student_mentoring_attachment_id);


--
-- Name: student_mentoring_followups student_mentoring_followups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_followups
    ADD CONSTRAINT student_mentoring_followups_pkey PRIMARY KEY (student_mentoring_followup_id);


--
-- Name: student_mentoring_reviews student_mentoring_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews
    ADD CONSTRAINT student_mentoring_reviews_pkey PRIMARY KEY (student_mentoring_review_id);


--
-- Name: student_mentoring_reviews student_mentoring_reviews_student_mentoring_session_id_revi_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews
    ADD CONSTRAINT student_mentoring_reviews_student_mentoring_session_id_revi_key UNIQUE (student_mentoring_session_id, reviewer_employee_id, review_level);


--
-- Name: student_mentoring_session_topics student_mentoring_session_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_session_topics
    ADD CONSTRAINT student_mentoring_session_topics_pkey PRIMARY KEY (student_mentoring_session_id, mentoring_topic_id);


--
-- Name: student_mentoring_sessions student_mentoring_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_pkey PRIMARY KEY (student_mentoring_session_id);


--
-- Name: student_parents student_parents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_pkey PRIMARY KEY (student_parent_id);


--
-- Name: student_parents student_parents_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_student_id_key UNIQUE (student_id);


--
-- Name: student_password_reset_audit student_password_reset_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_password_reset_audit
    ADD CONSTRAINT student_password_reset_audit_pkey PRIMARY KEY (student_password_reset_audit_id);


--
-- Name: student_registration_history student_registration_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_registration_history
    ADD CONSTRAINT student_registration_history_pkey PRIMARY KEY (student_registration_history_id);


--
-- Name: student_restore_history student_restore_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_restore_history
    ADD CONSTRAINT student_restore_history_pkey PRIMARY KEY (student_restore_history_id);


--
-- Name: student_reviewer_allotments student_reviewer_allotments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_pkey PRIMARY KEY (student_reviewer_allotment_id);


--
-- Name: student_scholarships student_scholarships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_scholarships
    ADD CONSTRAINT student_scholarships_pkey PRIMARY KEY (student_scholarship_id);


--
-- Name: student_section_history student_section_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_section_history
    ADD CONSTRAINT student_section_history_pkey PRIMARY KEY (history_id);


--
-- Name: student_status_history student_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_status_history
    ADD CONSTRAINT student_status_history_pkey PRIMARY KEY (student_status_history_id);


--
-- Name: student_statuses student_statuses_institute_id_status_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses
    ADD CONSTRAINT student_statuses_institute_id_status_code_key UNIQUE (institute_id, status_code);


--
-- Name: student_statuses student_statuses_institute_id_status_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses
    ADD CONSTRAINT student_statuses_institute_id_status_name_key UNIQUE (institute_id, status_name);


--
-- Name: student_statuses student_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses
    ADD CONSTRAINT student_statuses_pkey PRIMARY KEY (student_status_id);


--
-- Name: student_transport_allocations student_transport_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations
    ADD CONSTRAINT student_transport_allocations_pkey PRIMARY KEY (student_transport_id);


--
-- Name: student_transport_allocations student_transport_allocations_student_id_academic_year_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations
    ADD CONSTRAINT student_transport_allocations_student_id_academic_year_id_key UNIQUE (student_id, academic_year_id);


--
-- Name: students students_institution_id_admission_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_institution_id_admission_no_key UNIQUE (institution_id, admission_no);


--
-- Name: students students_institution_id_registration_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_institution_id_registration_no_key UNIQUE (institution_id, registration_no);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (student_id);


--
-- Name: students students_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_user_id_key UNIQUE (user_id);


--
-- Name: subject_components subject_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_components
    ADD CONSTRAINT subject_components_pkey PRIMARY KEY (subject_component_id);


--
-- Name: subject_components subject_components_subject_master_id_subject_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_components
    ADD CONSTRAINT subject_components_subject_master_id_subject_type_key UNIQUE (subject_master_id, subject_type);


--
-- Name: subject_masters subject_masters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_masters
    ADD CONSTRAINT subject_masters_pkey PRIMARY KEY (subject_master_id);


--
-- Name: subject_masters subject_masters_scope_check; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.subject_masters
    ADD CONSTRAINT subject_masters_scope_check CHECK (((programme_id IS NULL) = (semester_id IS NULL))) NOT VALID;


--
-- Name: subject_teacher_allocations subject_teacher_allocations_academic_year_id_batch_id_semes_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_academic_year_id_batch_id_semes_key UNIQUE (academic_year_id, batch_id, semester_id, section_id, subject_master_id, employee_id, allocation_role);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_pkey PRIMARY KEY (subject_teacher_allocation_id);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocation_subject_teacher_allocation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocation_subject_teacher_allocation_id_key UNIQUE (subject_teacher_allocation_id, from_date, to_date);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocations_pkey PRIMARY KEY (substitute_teacher_allocation_id);


--
-- Name: system_menus system_menus_menu_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_menus
    ADD CONSTRAINT system_menus_menu_code_key UNIQUE (menu_code);


--
-- Name: system_menus system_menus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_menus
    ADD CONSTRAINT system_menus_pkey PRIMARY KEY (menu_id);


--
-- Name: system_modules system_modules_module_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_modules
    ADD CONSTRAINT system_modules_module_code_key UNIQUE (module_code);


--
-- Name: system_modules system_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_modules
    ADD CONSTRAINT system_modules_pkey PRIMARY KEY (module_id);


--
-- Name: system_settings system_settings_institution_id_setting_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_institution_id_setting_key_key UNIQUE (institution_id, setting_key);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (setting_id);


--
-- Name: time_slots time_slots_institution_id_slot_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_slots
    ADD CONSTRAINT time_slots_institution_id_slot_name_key UNIQUE (institution_id, slot_name);


--
-- Name: time_slots time_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_slots
    ADD CONSTRAINT time_slots_pkey PRIMARY KEY (time_slot_id);


--
-- Name: timetable_entries timetable_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_entries
    ADD CONSTRAINT timetable_entries_pkey PRIMARY KEY (timetable_entry_id);


--
-- Name: transport_routes transport_routes_institution_id_route_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_routes
    ADD CONSTRAINT transport_routes_institution_id_route_code_key UNIQUE (institution_id, route_code);


--
-- Name: transport_routes transport_routes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_routes
    ADD CONSTRAINT transport_routes_pkey PRIMARY KEY (route_id);


--
-- Name: transport_stops transport_stops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_stops
    ADD CONSTRAINT transport_stops_pkey PRIMARY KEY (stop_id);


--
-- Name: programme_semester_definitions uq_programme_semester_definition; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT uq_programme_semester_definition UNIQUE (course_id, programme_batch_id, semester_id, class_type);


--
-- Name: user_accounts user_accounts_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_employee_id_key UNIQUE (employee_id);


--
-- Name: user_accounts user_accounts_login_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_login_id_key UNIQUE (login_id);


--
-- Name: user_accounts user_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_pkey PRIMARY KEY (user_id);


--
-- Name: user_permissions user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_pkey PRIMARY KEY (user_permission_id);


--
-- Name: user_permissions user_permissions_user_id_menu_id_permission_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_user_id_menu_id_permission_id_key UNIQUE (user_id, menu_id, permission_id);


--
-- Name: user_photos user_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_photos
    ADD CONSTRAINT user_photos_pkey PRIMARY KEY (user_photo_id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id, institution_id, department_id);


--
-- Name: user_status_history user_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_status_history
    ADD CONSTRAINT user_status_history_pkey PRIMARY KEY (user_status_history_id);


--
-- Name: user_types user_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_types
    ADD CONSTRAINT user_types_pkey PRIMARY KEY (user_type_id);


--
-- Name: user_types user_types_user_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_types
    ADD CONSTRAINT user_types_user_type_code_key UNIQUE (user_type_code);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (vehicle_id);


--
-- Name: vehicles vehicles_registration_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_registration_number_key UNIQUE (registration_number);


--
-- Name: idx_academic_periods_configuration; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_academic_periods_configuration ON academics.academic_periods USING btree (time_configuration_id);


--
-- Name: idx_timetable_entries_classroom; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_entries_classroom ON academics.timetable_entries USING btree (classroom_id, week_day_id, period_id);


--
-- Name: idx_timetable_entries_faculty; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_entries_faculty ON academics.timetable_entries USING btree (faculty_employee_id, week_day_id, period_id);


--
-- Name: idx_timetable_entries_room; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_entries_room ON academics.timetable_entries USING btree (room_id, week_day_id, period_id);


--
-- Name: idx_timetable_entries_timetable; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_entries_timetable ON academics.timetable_entries USING btree (timetable_id);


--
-- Name: idx_timetable_headers_academic_year; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_headers_academic_year ON academics.timetable_headers USING btree (academic_year_id);


--
-- Name: idx_timetable_headers_batch_semester; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_headers_batch_semester ON academics.timetable_headers USING btree (programme_batch_id, semester_id);


--
-- Name: idx_timetable_headers_section; Type: INDEX; Schema: academics; Owner: -
--

CREATE INDEX idx_timetable_headers_section ON academics.timetable_headers USING btree (programme_section_id);


--
-- Name: idx_sms_batches_created_at; Type: INDEX; Schema: communication; Owner: -
--

CREATE INDEX idx_sms_batches_created_at ON communication.sms_batches USING btree (created_at DESC);


--
-- Name: idx_sms_recipients_batch; Type: INDEX; Schema: communication; Owner: -
--

CREATE INDEX idx_sms_recipients_batch ON communication.sms_recipients USING btree (sms_batch_id);


--
-- Name: idx_sms_recipients_status; Type: INDEX; Schema: communication; Owner: -
--

CREATE INDEX idx_sms_recipients_status ON communication.sms_recipients USING btree (recipient_status);


--
-- Name: idx_counselling_date; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_counselling_date ON mentoring.student_counsellings USING btree (discussion_date DESC);


--
-- Name: idx_counselling_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_counselling_mentor ON mentoring.student_counsellings USING btree (mentor_id);


--
-- Name: idx_counselling_mode; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_counselling_mode ON mentoring.student_counsellings USING btree (communication_mode_id);


--
-- Name: idx_counselling_purpose; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_counselling_purpose ON mentoring.student_counsellings USING btree (counselling_purpose_id);


--
-- Name: idx_counselling_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_counselling_student ON mentoring.student_counsellings USING btree (student_id);


--
-- Name: idx_employee_mentor_eligibility_employee; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_employee_mentor_eligibility_employee ON mentoring.employee_mentor_eligibility USING btree (employee_id);


--
-- Name: idx_employee_mentor_eligibility_status; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_employee_mentor_eligibility_status ON mentoring.employee_mentor_eligibility USING btree (is_mentor_for_new_students, eligibility_status);


--
-- Name: idx_first_review_date; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_first_review_date ON mentoring.first_reviewer_remarks USING btree (review_date DESC);


--
-- Name: idx_first_review_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_first_review_mentor ON mentoring.first_reviewer_remarks USING btree (mentor_id);


--
-- Name: idx_first_review_reviewer; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_first_review_reviewer ON mentoring.first_reviewer_remarks USING btree (reviewer_id);


--
-- Name: idx_first_review_status; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_first_review_status ON mentoring.first_reviewer_remarks USING btree (review_status);


--
-- Name: idx_first_review_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_first_review_student ON mentoring.first_reviewer_remarks USING btree (student_id);


--
-- Name: idx_mentor_activity_student_date; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mentor_activity_student_date ON mentoring.student_counsellings USING btree (student_id, discussion_date);


--
-- Name: idx_mentor_assignment_changes_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mentor_assignment_changes_student ON mentoring.mentor_assignment_changes USING btree (student_id, changed_at DESC);


--
-- Name: idx_mentor_parent_activity_student_date; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mentor_parent_activity_student_date ON mentoring.parent_interactions USING btree (student_id, interaction_date);


--
-- Name: idx_mra_academic_year; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mra_academic_year ON mentoring.mentor_reviewer_allotments USING btree (academic_year_id);


--
-- Name: idx_mra_department; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mra_department ON mentoring.mentor_reviewer_allotments USING btree (department_id);


--
-- Name: idx_mra_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mra_mentor ON mentoring.mentor_reviewer_allotments USING btree (mentor_id);


--
-- Name: idx_mrad_reviewer; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mrad_reviewer ON mentoring.mentor_reviewer_allotment_details USING btree (reviewer_id);


--
-- Name: idx_mrad_role; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_mrad_role ON mentoring.mentor_reviewer_allotment_details USING btree (reviewer_role);


--
-- Name: idx_parent_interactions_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_parent_interactions_mentor ON mentoring.parent_interactions USING btree (mentor_id);


--
-- Name: idx_parent_interactions_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_parent_interactions_student ON mentoring.parent_interactions USING btree (student_id);


--
-- Name: idx_prospective_mentor_employee; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_prospective_mentor_employee ON mentoring.prospective_student_mentor_allotments USING btree (employee_id);


--
-- Name: idx_prospective_mentor_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_prospective_mentor_student ON mentoring.prospective_student_mentor_allotments USING btree (prospective_student_id);


--
-- Name: idx_reviewer_remarks_level; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_reviewer_remarks_level ON mentoring.counselling_reviewer_remarks USING btree (reviewer_level);


--
-- Name: idx_reviewer_remarks_reviewer; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_reviewer_remarks_reviewer ON mentoring.counselling_reviewer_remarks USING btree (reviewer_id);


--
-- Name: idx_student_counsellings_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_student_counsellings_mentor ON mentoring.student_counsellings USING btree (mentor_id);


--
-- Name: idx_student_counsellings_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE INDEX idx_student_counsellings_student ON mentoring.student_counsellings USING btree (student_id);


--
-- Name: uq_active_mentor_reviewer_allotment; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE UNIQUE INDEX uq_active_mentor_reviewer_allotment ON mentoring.mentor_reviewer_allotments USING btree (academic_year_id, mentor_id) WHERE ((allotment_status)::text = 'Active'::text);


--
-- Name: uq_active_prospective_student_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE UNIQUE INDEX uq_active_prospective_student_mentor ON mentoring.prospective_student_mentor_allotments USING btree (prospective_student_id) WHERE ((allotment_status)::text = 'Active'::text);


--
-- Name: uq_active_student_mentor; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE UNIQUE INDEX uq_active_student_mentor ON mentoring.student_mentor_allotments USING btree (academic_year_id, student_id) WHERE ((allotment_status)::text = 'Active'::text);


--
-- Name: uq_first_reviewer_student; Type: INDEX; Schema: mentoring; Owner: -
--

CREATE UNIQUE INDEX uq_first_reviewer_student ON mentoring.first_reviewer_remarks USING btree (academic_year_id, student_id, reviewer_id) WHERE ((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text]));


--
-- Name: course_initial_setup_batch_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX course_initial_setup_batch_idx ON public.course_initial_setup USING btree (batch_id);


--
-- Name: idx_attendance_sessions_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_sessions_date ON public.attendance_sessions USING btree (attendance_date, offering_id);


--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at);


--
-- Name: idx_audit_logs_table_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_table_record ON public.audit_logs USING btree (table_name, record_id);


--
-- Name: idx_class_teacher_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_class_teacher_subject ON public.class_teacher_allocations USING btree (subject_master_id);


--
-- Name: idx_classroom_unavailability_classroom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_classroom_unavailability_classroom ON public.classroom_unavailability USING btree (classroom_id);


--
-- Name: idx_classrooms_building; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_classrooms_building ON public.classrooms USING btree (building_id);


--
-- Name: idx_classrooms_campus; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_classrooms_campus ON public.classrooms USING btree (campus_id);


--
-- Name: idx_classrooms_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_classrooms_type ON public.classrooms USING btree (classroom_type_id);


--
-- Name: idx_course_offerings_term_section; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_course_offerings_term_section ON public.course_offerings USING btree (term_id, section_id);


--
-- Name: idx_dashboard_messages_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dashboard_messages_department ON public.dashboard_messages USING btree (department_id);


--
-- Name: idx_dashboard_messages_display; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dashboard_messages_display ON public.dashboard_messages USING btree (show_on_dashboard, status, display_from, display_to, display_order);


--
-- Name: idx_dashboard_messages_programme; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dashboard_messages_programme ON public.dashboard_messages USING btree (programme_id);


--
-- Name: idx_dashboard_notice_audiences_notice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dashboard_notice_audiences_notice ON public.dashboard_notice_audiences USING btree (notice_id);


--
-- Name: idx_dashboard_notices_academic_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dashboard_notices_academic_year ON public.dashboard_notices USING btree (academic_year_id);


--
-- Name: idx_dashboard_notices_publish; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dashboard_notices_publish ON public.dashboard_notices USING btree (notice_status, publish_from, publish_to, is_pinned);


--
-- Name: idx_employees_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_department ON public.employees USING btree (department_id);


--
-- Name: idx_fee_demands_student_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fee_demands_student_status ON public.student_fee_demands USING btree (student_id, status);


--
-- Name: idx_fee_payments_student_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fee_payments_student_date ON public.fee_payments USING btree (student_id, payment_date);


--
-- Name: idx_fee_undertakings_student_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fee_undertakings_student_status ON public.student_fee_undertakings USING btree (student_id, undertaking_status);


--
-- Name: idx_library_book_issues_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_library_book_issues_pending ON public.library_book_issues USING btree (due_date) WHERE (returned_at IS NULL);


--
-- Name: idx_login_history_login_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_login_history_login_at ON public.login_history USING btree (login_at DESC);


--
-- Name: idx_login_history_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_login_history_status ON public.login_history USING btree (login_status);


--
-- Name: idx_login_history_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_login_history_user ON public.login_history USING btree (user_id);


--
-- Name: idx_mentoring_reviews_reviewer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mentoring_reviews_reviewer ON public.student_mentoring_reviews USING btree (reviewer_employee_id, review_status);


--
-- Name: idx_mentoring_sessions_mentor_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mentoring_sessions_mentor_date ON public.student_mentoring_sessions USING btree (mentor_employee_id, mentoring_date DESC);


--
-- Name: idx_mentoring_sessions_student_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mentoring_sessions_student_date ON public.student_mentoring_sessions USING btree (student_id, mentoring_date DESC);


--
-- Name: idx_notifications_user_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_read ON public.notifications USING btree (user_id, is_read);


--
-- Name: idx_programme_semester_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_programme_semester_batch ON public.programme_semester_definitions USING btree (programme_batch_id);


--
-- Name: idx_programme_semester_course; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_programme_semester_course ON public.programme_semester_definitions USING btree (course_id);


--
-- Name: idx_programme_semester_semester; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_programme_semester_semester ON public.programme_semester_definitions USING btree (semester_id);


--
-- Name: idx_semester_promotion_active_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_semester_promotion_active_batch ON public.programme_semester_definitions USING btree (programme_batch_id, is_active, semester_id);


--
-- Name: idx_student_attendance_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_student_attendance_student ON public.student_attendance USING btree (student_id);


--
-- Name: idx_student_documents_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_student_documents_student ON public.student_documents USING btree (student_id);


--
-- Name: idx_student_marks_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_student_marks_student ON public.student_marks USING btree (student_id);


--
-- Name: idx_students_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_department ON public.students USING btree (department_id);


--
-- Name: idx_students_programme; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_programme ON public.students USING btree (programme_id);


--
-- Name: idx_students_programme_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_programme_batch ON public.students USING btree (programme_id, batch_id);


--
-- Name: idx_students_section; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_section ON public.students USING btree (section_id);


--
-- Name: idx_students_semester_section; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_semester_section ON public.students USING btree (semester_id, section_id);


--
-- Name: idx_students_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_status ON public.students USING btree (student_status_id, is_active, is_deleted);


--
-- Name: idx_users_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_full_name ON public.users USING btree (full_name);


--
-- Name: idx_users_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_status ON public.users USING btree (user_status);


--
-- Name: idx_users_user_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_user_type ON public.users USING btree (user_type_id);


--
-- Name: login_history_login_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX login_history_login_at_idx ON public.login_history USING btree (login_at DESC);


--
-- Name: login_history_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX login_history_user_id_idx ON public.login_history USING btree (user_id);


--
-- Name: section_definitions_course_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX section_definitions_course_idx ON public.section_definitions USING btree (course_id);


--
-- Name: section_definitions_mapping_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX section_definitions_mapping_uq ON public.section_definitions USING btree (lower((section_name)::text), section_master_id, admission_course_id, course_id);


--
-- Name: section_masters_name_normalized_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX section_masters_name_normalized_uq ON public.section_masters USING btree (lower(TRIM(BOTH FROM section_master_name)));


--
-- Name: semesters_id_programme_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX semesters_id_programme_uq ON public.semesters USING btree (semester_id, programme_id);


--
-- Name: subject_masters_department_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subject_masters_department_idx ON public.subject_masters USING btree (department_id);


--
-- Name: subject_masters_legacy_code_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subject_masters_legacy_code_uq ON public.subject_masters USING btree (subject_code) WHERE ((programme_id IS NULL) AND (semester_id IS NULL));


--
-- Name: subject_masters_programme_semester_code_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subject_masters_programme_semester_code_uq ON public.subject_masters USING btree (programme_id, semester_id, upper((subject_code)::text)) WHERE ((programme_id IS NOT NULL) AND (semester_id IS NOT NULL));


--
-- Name: uq_active_primary_student_mentor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_active_primary_student_mentor ON public.student_mentor_allotments USING btree (student_id) WHERE ((is_active = true) AND (is_primary = true) AND (effective_to IS NULL));


--
-- Name: uq_class_subject_teacher_role; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_class_subject_teacher_role ON public.class_teacher_allocations USING btree (academic_year_id, batch_id, semester_id, section_id, student_group, subject_master_id, teacher_type) WHERE ((subject_master_id IS NOT NULL) AND ((status)::text = 'ACTIVE'::text));


--
-- Name: uq_common_master_type_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_common_master_type_code ON public.common_master_values USING btree (master_type_id, value_code);


--
-- Name: uq_common_master_type_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_common_master_type_name ON public.common_master_values USING btree (master_type_id, value_name);


--
-- Name: uq_legacy_class_teacher; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_legacy_class_teacher ON public.class_teacher_allocations USING btree (academic_year_id, batch_id, semester_id, section_id, student_group) WHERE ((subject_master_id IS NULL) AND ((status)::text = 'ACTIVE'::text));


--
-- Name: uq_library_authors_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_library_authors_code ON public.library_authors USING btree (author_code);


--
-- Name: uq_library_book_issues_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_library_book_issues_number ON public.library_book_issues USING btree (issue_number);


--
-- Name: uq_library_study_material_issue_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_library_study_material_issue_number ON public.library_study_material_issues USING btree (issue_number);


--
-- Name: uq_student_mentor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_student_mentor ON public.student_mentor_allotments USING btree (academic_year_id, student_id) WHERE ((status)::text = 'Active'::text);


--
-- Name: uq_students_institute_admission; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_students_institute_admission ON public.students USING btree (institute_id, admission_number) WHERE (admission_number IS NOT NULL);


--
-- Name: uq_students_institute_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_students_institute_code ON public.students USING btree (institute_id, student_code);


--
-- Name: uq_students_institute_registration; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_students_institute_registration ON public.students USING btree (institute_id, registration_number) WHERE (registration_number IS NOT NULL);


--
-- Name: uq_users_employee_link; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_users_employee_link ON public.users USING btree (employee_id) WHERE (employee_id IS NOT NULL);


--
-- Name: uq_users_student_link; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_users_student_link ON public.users USING btree (student_id) WHERE (student_id IS NOT NULL);


--
-- Name: vw_mentor_allotment_report _RETURN; Type: RULE; Schema: mentoring; Owner: -
--

CREATE OR REPLACE VIEW mentoring.vw_mentor_allotment_report AS
 SELECT e.employee_id,
    m.mentor_id,
    e.first_name,
    e.middle_name,
    e.last_name,
    d.department_name,
    des.designation_name,
    COALESCE(NULLIF((e.employee_category)::text, ''::text), (des.category)::text, 'Staff'::text) AS category_name,
    COALESCE(m.maximum_students, 30) AS maximum_students,
    (count(DISTINCT sma.student_id) FILTER (WHERE ((sma.allotment_status)::text = 'Active'::text)))::integer AS students_allotted,
    (COALESCE(m.maximum_students, 30) - (count(DISTINCT sma.student_id) FILTER (WHERE ((sma.allotment_status)::text = 'Active'::text)))::integer) AS available_capacity,
    COALESCE(m.mentor_status, 'Inactive'::character varying) AS mentor_status
   FROM ((((public.employees e
     LEFT JOIN public.departments d ON ((d.department_id = e.department_id)))
     LEFT JOIN public.designations des ON ((des.designation_id = e.designation_id)))
     LEFT JOIN mentoring.mentors m ON ((m.employee_id = e.employee_id)))
     LEFT JOIN mentoring.student_mentor_allotments sma ON ((sma.mentor_id = m.mentor_id)))
  WHERE (upper((COALESCE(e.status, 'ACTIVE'::character varying))::text) = 'ACTIVE'::text)
  GROUP BY e.employee_id, m.mentor_id, d.department_name, des.designation_name, des.category, m.maximum_students, m.mentor_status;


--
-- Name: vw_student_counsellings_reviews _RETURN; Type: RULE; Schema: mentoring; Owner: -
--

CREATE OR REPLACE VIEW mentoring.vw_student_counsellings_reviews AS
 SELECT sc.student_counselling_id,
    sc.academic_year_id,
    sc.student_id,
    sc.mentor_id,
    sc.discussion_date,
    COALESCE(cm.mode_name, sc.communication_mode) AS communication_mode,
    COALESCE(cp.purpose_name, sc.purpose) AS purpose,
    sc.detailed_discussion,
    sc.mentor_remarks,
    sc.counselling_status,
    max(crr.reviewer_remarks) FILTER (WHERE ((crr.reviewer_level)::text = 'Reviewer 1'::text)) AS reviewer_1_remarks,
    max(crr.reviewer_remarks) FILTER (WHERE ((crr.reviewer_level)::text = 'Reviewer 2'::text)) AS reviewer_2_remarks,
    max(crr.reviewer_remarks) FILTER (WHERE ((crr.reviewer_level)::text = 'Chief Reviewer'::text)) AS chief_reviewer_remarks
   FROM (((mentoring.student_counsellings sc
     LEFT JOIN mentoring.communication_modes cm ON ((cm.communication_mode_id = sc.communication_mode_id)))
     LEFT JOIN mentoring.counselling_purposes cp ON ((cp.counselling_purpose_id = sc.counselling_purpose_id)))
     LEFT JOIN mentoring.counselling_reviewer_remarks crr ON ((crr.student_counselling_id = sc.student_counselling_id)))
  GROUP BY sc.student_counselling_id, cm.mode_name, cp.purpose_name;


--
-- Name: academic_breaks trg_validate_academic_break; Type: TRIGGER; Schema: academics; Owner: -
--

CREATE TRIGGER trg_validate_academic_break BEFORE INSERT OR UPDATE ON academics.academic_breaks FOR EACH ROW EXECUTE FUNCTION academics.validate_academic_break();


--
-- Name: timetable_entries trg_validate_timetable_entry; Type: TRIGGER; Schema: academics; Owner: -
--

CREATE TRIGGER trg_validate_timetable_entry BEFORE INSERT OR UPDATE ON academics.timetable_entries FOR EACH ROW EXECUTE FUNCTION academics.validate_timetable_entry();


--
-- Name: mentor_reviewer_allotment_details trg_validate_mentor_reviewer_detail; Type: TRIGGER; Schema: mentoring; Owner: -
--

CREATE TRIGGER trg_validate_mentor_reviewer_detail BEFORE INSERT OR UPDATE ON mentoring.mentor_reviewer_allotment_details FOR EACH ROW EXECUTE FUNCTION mentoring.validate_mentor_reviewer_detail();


--
-- Name: users trg_validate_user_type_link; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validate_user_type_link BEFORE INSERT OR UPDATE OF user_type_id, employee_id, student_id ON public.users FOR EACH ROW EXECUTE FUNCTION public.validate_user_type_link();


--
-- Name: user_logins user_logins_created_by_fkey; Type: FK CONSTRAINT; Schema: ABDC_DB; Owner: -
--

ALTER TABLE ONLY "ABDC_DB".user_logins
    ADD CONSTRAINT user_logins_created_by_fkey FOREIGN KEY (created_by) REFERENCES "ABDC_DB".user_logins(user_id);


--
-- Name: academic_breaks academic_breaks_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_breaks
    ADD CONSTRAINT academic_breaks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: academic_breaks academic_breaks_time_configuration_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_breaks
    ADD CONSTRAINT academic_breaks_time_configuration_id_fkey FOREIGN KEY (time_configuration_id) REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE CASCADE;


--
-- Name: academic_breaks academic_breaks_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_breaks
    ADD CONSTRAINT academic_breaks_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: academic_periods academic_periods_time_configuration_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_periods
    ADD CONSTRAINT academic_periods_time_configuration_id_fkey FOREIGN KEY (time_configuration_id) REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE CASCADE;


--
-- Name: academic_time_configuration_days academic_time_configuration_days_time_configuration_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configuration_days
    ADD CONSTRAINT academic_time_configuration_days_time_configuration_id_fkey FOREIGN KEY (time_configuration_id) REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE CASCADE;


--
-- Name: academic_time_configuration_days academic_time_configuration_days_week_day_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configuration_days
    ADD CONSTRAINT academic_time_configuration_days_week_day_id_fkey FOREIGN KEY (week_day_id) REFERENCES academics.week_days(week_day_id) ON DELETE RESTRICT;


--
-- Name: academic_time_configurations academic_time_configurations_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configurations
    ADD CONSTRAINT academic_time_configurations_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE CASCADE;


--
-- Name: academic_time_configurations academic_time_configurations_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configurations
    ADD CONSTRAINT academic_time_configurations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: academic_time_configurations academic_time_configurations_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.academic_time_configurations
    ADD CONSTRAINT academic_time_configurations_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: attendance_calendar_dates attendance_calendar_dates_attendance_calendar_setting_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_dates
    ADD CONSTRAINT attendance_calendar_dates_attendance_calendar_setting_id_fkey FOREIGN KEY (attendance_calendar_setting_id) REFERENCES academics.attendance_calendar_settings(attendance_calendar_setting_id) ON DELETE CASCADE;


--
-- Name: attendance_calendar_settings attendance_calendar_settings_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: attendance_calendar_settings attendance_calendar_settings_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: attendance_calendar_settings attendance_calendar_settings_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: attendance_calendar_settings attendance_calendar_settings_programme_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: attendance_calendar_settings attendance_calendar_settings_programme_section_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_programme_section_id_fkey FOREIGN KEY (programme_section_id) REFERENCES public.sections(section_id);


--
-- Name: attendance_calendar_settings attendance_calendar_settings_semester_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_settings
    ADD CONSTRAINT attendance_calendar_settings_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: attendance_calendar_weekdays attendance_calendar_weekdays_attendance_calendar_setting_i_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.attendance_calendar_weekdays
    ADD CONSTRAINT attendance_calendar_weekdays_attendance_calendar_setting_i_fkey FOREIGN KEY (attendance_calendar_setting_id) REFERENCES academics.attendance_calendar_settings(attendance_calendar_setting_id) ON DELETE CASCADE;


--
-- Name: course_outcomes course_outcomes_co_code_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_co_code_id_fkey FOREIGN KEY (co_code_id) REFERENCES academics.course_outcome_codes(co_code_id);


--
-- Name: course_outcomes course_outcomes_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: course_outcomes course_outcomes_faculty_employee_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_faculty_employee_id_fkey FOREIGN KEY (faculty_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: course_outcomes course_outcomes_subject_master_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_subject_master_id_fkey FOREIGN KEY (subject_master_id) REFERENCES public.subject_masters(subject_master_id);


--
-- Name: course_outcomes course_outcomes_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.course_outcomes
    ADD CONSTRAINT course_outcomes_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_assigned_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(user_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_faculty_employee_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_faculty_employee_id_fkey FOREIGN KEY (faculty_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_programme_section_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_programme_section_id_fkey FOREIGN KEY (programme_section_id) REFERENCES public.sections(section_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_semester_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: faculty_subject_assignments faculty_subject_assignments_subject_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.faculty_subject_assignments
    ADD CONSTRAINT faculty_subject_assignments_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject_masters(subject_master_id);


--
-- Name: lecture_notes lecture_notes_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lecture_notes
    ADD CONSTRAINT lecture_notes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: lecture_notes lecture_notes_subject_master_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lecture_notes
    ADD CONSTRAINT lecture_notes_subject_master_id_fkey FOREIGN KEY (subject_master_id) REFERENCES public.subject_masters(subject_master_id);


--
-- Name: lecture_notes lecture_notes_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lecture_notes
    ADD CONSTRAINT lecture_notes_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_books lesson_plan_books_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_books
    ADD CONSTRAINT lesson_plan_books_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_books lesson_plan_books_lesson_plan_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_books
    ADD CONSTRAINT lesson_plan_books_lesson_plan_id_fkey FOREIGN KEY (lesson_plan_id) REFERENCES academics.lesson_plan_headers(lesson_plan_id) ON DELETE CASCADE;


--
-- Name: lesson_plan_books lesson_plan_books_preferred_book_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_books
    ADD CONSTRAINT lesson_plan_books_preferred_book_id_fkey FOREIGN KEY (preferred_book_id) REFERENCES public.preferred_books(preferred_book_id);


--
-- Name: lesson_plan_headers lesson_plan_headers_approved_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers
    ADD CONSTRAINT lesson_plan_headers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_headers lesson_plan_headers_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers
    ADD CONSTRAINT lesson_plan_headers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_headers lesson_plan_headers_faculty_subject_assignment_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers
    ADD CONSTRAINT lesson_plan_headers_faculty_subject_assignment_id_fkey FOREIGN KEY (faculty_subject_assignment_id) REFERENCES academics.faculty_subject_assignments(faculty_subject_assignment_id) ON DELETE CASCADE;


--
-- Name: lesson_plan_headers lesson_plan_headers_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_headers
    ADD CONSTRAINT lesson_plan_headers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_topic_outcomes lesson_plan_topic_outcomes_course_outcome_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topic_outcomes
    ADD CONSTRAINT lesson_plan_topic_outcomes_course_outcome_id_fkey FOREIGN KEY (course_outcome_id) REFERENCES academics.course_outcomes(course_outcome_id);


--
-- Name: lesson_plan_topic_outcomes lesson_plan_topic_outcomes_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topic_outcomes
    ADD CONSTRAINT lesson_plan_topic_outcomes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_topic_outcomes lesson_plan_topic_outcomes_lesson_plan_topic_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topic_outcomes
    ADD CONSTRAINT lesson_plan_topic_outcomes_lesson_plan_topic_id_fkey FOREIGN KEY (lesson_plan_topic_id) REFERENCES academics.lesson_plan_topics(lesson_plan_topic_id) ON DELETE CASCADE;


--
-- Name: lesson_plan_topics lesson_plan_topics_course_outcome_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_course_outcome_id_fkey FOREIGN KEY (course_outcome_id) REFERENCES academics.course_outcomes(course_outcome_id);


--
-- Name: lesson_plan_topics lesson_plan_topics_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: lesson_plan_topics lesson_plan_topics_lesson_plan_book_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_lesson_plan_book_id_fkey FOREIGN KEY (lesson_plan_book_id) REFERENCES academics.lesson_plan_books(lesson_plan_book_id);


--
-- Name: lesson_plan_topics lesson_plan_topics_lesson_plan_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_lesson_plan_id_fkey FOREIGN KEY (lesson_plan_id) REFERENCES academics.lesson_plan_headers(lesson_plan_id) ON DELETE CASCADE;


--
-- Name: lesson_plan_topics lesson_plan_topics_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.lesson_plan_topics
    ADD CONSTRAINT lesson_plan_topics_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: timetable_change_logs timetable_change_logs_changed_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_change_logs
    ADD CONSTRAINT timetable_change_logs_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: timetable_change_logs timetable_change_logs_timetable_entry_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_change_logs
    ADD CONSTRAINT timetable_change_logs_timetable_entry_id_fkey FOREIGN KEY (timetable_entry_id) REFERENCES academics.timetable_entries(timetable_entry_id) ON DELETE SET NULL;


--
-- Name: timetable_change_logs timetable_change_logs_timetable_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_change_logs
    ADD CONSTRAINT timetable_change_logs_timetable_id_fkey FOREIGN KEY (timetable_id) REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE;


--
-- Name: timetable_entries timetable_entries_classroom_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_classroom_id_fkey FOREIGN KEY (classroom_id) REFERENCES public.classrooms(classroom_id) ON DELETE RESTRICT;


--
-- Name: timetable_entries timetable_entries_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: timetable_entries timetable_entries_faculty_employee_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_faculty_employee_id_fkey FOREIGN KEY (faculty_employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: timetable_entries timetable_entries_period_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_period_id_fkey FOREIGN KEY (period_id) REFERENCES academics.academic_periods(period_id) ON DELETE RESTRICT;


--
-- Name: timetable_entries timetable_entries_room_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(room_id) ON DELETE RESTRICT;


--
-- Name: timetable_entries timetable_entries_subject_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject_masters(subject_master_id) ON DELETE RESTRICT;


--
-- Name: timetable_entries timetable_entries_subject_teacher_allocation_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_subject_teacher_allocation_id_fkey FOREIGN KEY (subject_teacher_allocation_id) REFERENCES public.subject_teacher_allocations(subject_teacher_allocation_id) ON DELETE RESTRICT;


--
-- Name: timetable_entries timetable_entries_timetable_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_timetable_id_fkey FOREIGN KEY (timetable_id) REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE;


--
-- Name: timetable_entries timetable_entries_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: timetable_entries timetable_entries_week_day_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_entries
    ADD CONSTRAINT timetable_entries_week_day_id_fkey FOREIGN KEY (week_day_id) REFERENCES academics.week_days(week_day_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_created_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: timetable_headers timetable_headers_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_programme_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_programme_section_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_programme_section_id_fkey FOREIGN KEY (programme_section_id) REFERENCES public.sections(section_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_published_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_published_by_fkey FOREIGN KEY (published_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: timetable_headers timetable_headers_semester_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_time_configuration_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_time_configuration_id_fkey FOREIGN KEY (time_configuration_id) REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE RESTRICT;


--
-- Name: timetable_headers timetable_headers_updated_by_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_headers
    ADD CONSTRAINT timetable_headers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: timetable_working_days timetable_working_days_timetable_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_working_days
    ADD CONSTRAINT timetable_working_days_timetable_id_fkey FOREIGN KEY (timetable_id) REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE;


--
-- Name: timetable_working_days timetable_working_days_week_day_id_fkey; Type: FK CONSTRAINT; Schema: academics; Owner: -
--

ALTER TABLE ONLY academics.timetable_working_days
    ADD CONSTRAINT timetable_working_days_week_day_id_fkey FOREIGN KEY (week_day_id) REFERENCES academics.week_days(week_day_id) ON DELETE RESTRICT;


--
-- Name: sms_batches sms_batches_created_by_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_batches
    ADD CONSTRAINT sms_batches_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: sms_batches sms_batches_sms_template_id_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_batches
    ADD CONSTRAINT sms_batches_sms_template_id_fkey FOREIGN KEY (sms_template_id) REFERENCES communication.sms_templates(sms_template_id) ON DELETE SET NULL;


--
-- Name: sms_recipients sms_recipients_employee_id_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_recipients
    ADD CONSTRAINT sms_recipients_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: sms_recipients sms_recipients_sms_batch_id_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_recipients
    ADD CONSTRAINT sms_recipients_sms_batch_id_fkey FOREIGN KEY (sms_batch_id) REFERENCES communication.sms_batches(sms_batch_id) ON DELETE CASCADE;


--
-- Name: sms_recipients sms_recipients_student_id_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_recipients
    ADD CONSTRAINT sms_recipients_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE SET NULL;


--
-- Name: sms_templates sms_templates_created_by_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_templates
    ADD CONSTRAINT sms_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: sms_templates sms_templates_updated_by_fkey; Type: FK CONSTRAINT; Schema: communication; Owner: -
--

ALTER TABLE ONLY communication.sms_templates
    ADD CONSTRAINT sms_templates_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: counselling_followups counselling_followups_assigned_to_employee_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_followups
    ADD CONSTRAINT counselling_followups_assigned_to_employee_id_fkey FOREIGN KEY (assigned_to_employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: counselling_followups counselling_followups_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_followups
    ADD CONSTRAINT counselling_followups_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: counselling_followups counselling_followups_student_counselling_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_followups
    ADD CONSTRAINT counselling_followups_student_counselling_id_fkey FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE CASCADE;


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remarks_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks
    ADD CONSTRAINT counselling_reviewer_remarks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remarks_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks
    ADD CONSTRAINT counselling_reviewer_remarks_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remarks_student_counselling_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks
    ADD CONSTRAINT counselling_reviewer_remarks_student_counselling_id_fkey FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE CASCADE;


--
-- Name: counselling_reviewer_remarks counselling_reviewer_remarks_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.counselling_reviewer_remarks
    ADD CONSTRAINT counselling_reviewer_remarks_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: employee_mentor_eligibility employee_mentor_eligibility_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility
    ADD CONSTRAINT employee_mentor_eligibility_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: employee_mentor_eligibility employee_mentor_eligibility_employee_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility
    ADD CONSTRAINT employee_mentor_eligibility_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE CASCADE;


--
-- Name: employee_mentor_eligibility_history employee_mentor_eligibility_h_employee_mentor_eligibility__fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility_history
    ADD CONSTRAINT employee_mentor_eligibility_h_employee_mentor_eligibility__fkey FOREIGN KEY (employee_mentor_eligibility_id) REFERENCES mentoring.employee_mentor_eligibility(employee_mentor_eligibility_id) ON DELETE CASCADE;


--
-- Name: employee_mentor_eligibility_history employee_mentor_eligibility_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility_history
    ADD CONSTRAINT employee_mentor_eligibility_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: employee_mentor_eligibility employee_mentor_eligibility_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.employee_mentor_eligibility
    ADD CONSTRAINT employee_mentor_eligibility_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE RESTRICT;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_mentor_reviewer_allotment_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_mentor_reviewer_allotment_id_fkey FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE SET NULL;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_student_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: first_reviewer_remarks first_reviewer_remarks_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.first_reviewer_remarks
    ADD CONSTRAINT first_reviewer_remarks_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentors fk_mentor_employee_eligibility; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT fk_mentor_employee_eligibility FOREIGN KEY (employee_mentor_eligibility_id) REFERENCES mentoring.employee_mentor_eligibility(employee_mentor_eligibility_id) ON DELETE SET NULL;


--
-- Name: mentor_assignment_changes mentor_assignment_changes_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes
    ADD CONSTRAINT mentor_assignment_changes_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: mentor_assignment_changes mentor_assignment_changes_changed_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes
    ADD CONSTRAINT mentor_assignment_changes_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id);


--
-- Name: mentor_assignment_changes mentor_assignment_changes_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes
    ADD CONSTRAINT mentor_assignment_changes_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id);


--
-- Name: mentor_assignment_changes mentor_assignment_changes_previous_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes
    ADD CONSTRAINT mentor_assignment_changes_previous_mentor_id_fkey FOREIGN KEY (previous_mentor_id) REFERENCES mentoring.mentors(mentor_id);


--
-- Name: mentor_assignment_changes mentor_assignment_changes_student_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_assignment_changes
    ADD CONSTRAINT mentor_assignment_changes_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details
    ADD CONSTRAINT mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_fkey FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE CASCADE;


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_allotment_details_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details
    ADD CONSTRAINT mentor_reviewer_allotment_details_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentor_reviewer_allotment_details mentor_reviewer_allotment_details_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotment_details
    ADD CONSTRAINT mentor_reviewer_allotment_details_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments
    ADD CONSTRAINT mentor_reviewer_allotments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE RESTRICT;


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotments_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments
    ADD CONSTRAINT mentor_reviewer_allotments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotments_department_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments
    ADD CONSTRAINT mentor_reviewer_allotments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotments_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments
    ADD CONSTRAINT mentor_reviewer_allotments_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: mentor_reviewer_allotments mentor_reviewer_allotments_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_allotments
    ADD CONSTRAINT mentor_reviewer_allotments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentor_reviewer_change_history mentor_reviewer_change_histor_mentor_reviewer_allotment_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_change_history
    ADD CONSTRAINT mentor_reviewer_change_histor_mentor_reviewer_allotment_id_fkey FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE CASCADE;


--
-- Name: mentor_reviewer_change_history mentor_reviewer_change_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_change_history
    ADD CONSTRAINT mentor_reviewer_change_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentor_reviewer_change_history mentor_reviewer_change_history_new_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_change_history
    ADD CONSTRAINT mentor_reviewer_change_history_new_reviewer_id_fkey FOREIGN KEY (new_reviewer_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: mentor_reviewer_change_history mentor_reviewer_change_history_old_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentor_reviewer_change_history
    ADD CONSTRAINT mentor_reviewer_change_history_old_reviewer_id_fkey FOREIGN KEY (old_reviewer_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: mentors mentors_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT mentors_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentors mentors_department_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT mentors_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: mentors mentors_employee_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT mentors_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: mentors mentors_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.mentors
    ADD CONSTRAINT mentors_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: parent_interactions parent_interactions_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions
    ADD CONSTRAINT parent_interactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: parent_interactions parent_interactions_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions
    ADD CONSTRAINT parent_interactions_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT;


--
-- Name: parent_interactions parent_interactions_student_counselling_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions
    ADD CONSTRAINT parent_interactions_student_counselling_id_fkey FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE SET NULL;


--
-- Name: parent_interactions parent_interactions_student_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions
    ADD CONSTRAINT parent_interactions_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: parent_interactions parent_interactions_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.parent_interactions
    ADD CONSTRAINT parent_interactions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotmen_prospective_student_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotmen_prospective_student_id_fkey FOREIGN KEY (prospective_student_id) REFERENCES public.prospective_students(prospective_student_id) ON DELETE CASCADE;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_employee_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: reviewers reviewers_employee_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.reviewers
    ADD CONSTRAINT reviewers_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- Name: student_counsellings student_counsellings_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE RESTRICT;


--
-- Name: student_counsellings student_counsellings_communication_mode_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_communication_mode_id_fkey FOREIGN KEY (communication_mode_id) REFERENCES mentoring.communication_modes(communication_mode_id) ON DELETE RESTRICT;


--
-- Name: student_counsellings student_counsellings_counselling_purpose_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_counselling_purpose_id_fkey FOREIGN KEY (counselling_purpose_id) REFERENCES mentoring.counselling_purposes(counselling_purpose_id) ON DELETE RESTRICT;


--
-- Name: student_counsellings student_counsellings_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_counsellings student_counsellings_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT;


--
-- Name: student_counsellings student_counsellings_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id) ON DELETE SET NULL;


--
-- Name: student_counsellings student_counsellings_programme_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE SET NULL;


--
-- Name: student_counsellings student_counsellings_programme_section_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_programme_section_id_fkey FOREIGN KEY (programme_section_id) REFERENCES public.sections(section_id) ON DELETE SET NULL;


--
-- Name: student_counsellings student_counsellings_semester_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE SET NULL;


--
-- Name: student_counsellings student_counsellings_student_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_counsellings student_counsellings_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_counsellings
    ADD CONSTRAINT student_counsellings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE RESTRICT;


--
-- Name: student_mentor_allotments student_mentor_allotments_created_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_mentor_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT;


--
-- Name: student_mentor_allotments student_mentor_allotments_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_programme_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_programme_section_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_programme_section_id_fkey FOREIGN KEY (programme_section_id) REFERENCES public.sections(section_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_semester_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_student_id_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_mentor_allotments student_mentor_allotments_updated_by_fkey; Type: FK CONSTRAINT; Schema: mentoring; Owner: -
--

ALTER TABLE ONLY mentoring.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: permission_change_history permission_change_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history
    ADD CONSTRAINT permission_change_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.user_accounts(user_id);


--
-- Name: permission_change_history permission_change_history_menu_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history
    ADD CONSTRAINT permission_change_history_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES permission_management.system_menus(menu_id);


--
-- Name: permission_change_history permission_change_history_permission_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history
    ADD CONSTRAINT permission_change_history_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permission_management.permissions(permission_id);


--
-- Name: permission_change_history permission_change_history_role_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history
    ADD CONSTRAINT permission_change_history_role_id_fkey FOREIGN KEY (role_id) REFERENCES permission_management.roles(role_id);


--
-- Name: permission_change_history permission_change_history_user_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.permission_change_history
    ADD CONSTRAINT permission_change_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id);


--
-- Name: role_permissions role_permissions_menu_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.role_permissions
    ADD CONSTRAINT role_permissions_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES permission_management.system_menus(menu_id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permission_management.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES permission_management.roles(role_id) ON DELETE CASCADE;


--
-- Name: system_menus system_menus_module_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_menus
    ADD CONSTRAINT system_menus_module_id_fkey FOREIGN KEY (module_id) REFERENCES permission_management.system_modules(module_id) ON DELETE CASCADE;


--
-- Name: system_menus system_menus_parent_menu_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.system_menus
    ADD CONSTRAINT system_menus_parent_menu_id_fkey FOREIGN KEY (parent_menu_id) REFERENCES permission_management.system_menus(menu_id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions
    ADD CONSTRAINT user_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.user_accounts(user_id);


--
-- Name: user_permissions user_permissions_menu_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions
    ADD CONSTRAINT user_permissions_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES permission_management.system_menus(menu_id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions
    ADD CONSTRAINT user_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permission_management.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_user_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_permissions
    ADD CONSTRAINT user_permissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_assigned_by_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_roles
    ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.user_accounts(user_id);


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES permission_management.roles(role_id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: permission_management; Owner: -
--

ALTER TABLE ONLY permission_management.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id) ON DELETE CASCADE;


--
-- Name: academic_terms academic_terms_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_terms
    ADD CONSTRAINT academic_terms_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: academic_years academic_years_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years
    ADD CONSTRAINT academic_years_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: admission_batches admission_batches_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_batches
    ADD CONSTRAINT admission_batches_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: admission_categories admission_categories_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories
    ADD CONSTRAINT admission_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: admission_categories admission_categories_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories
    ADD CONSTRAINT admission_categories_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: admission_categories admission_categories_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_categories
    ADD CONSTRAINT admission_categories_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: approval_actions approval_actions_action_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_actions
    ADD CONSTRAINT approval_actions_action_by_fkey FOREIGN KEY (action_by) REFERENCES public.users(user_id);


--
-- Name: approval_actions approval_actions_approval_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_actions
    ADD CONSTRAINT approval_actions_approval_request_id_fkey FOREIGN KEY (approval_request_id) REFERENCES public.approval_requests(approval_request_id) ON DELETE CASCADE;


--
-- Name: approval_requests approval_requests_current_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_current_approver_id_fkey FOREIGN KEY (current_approver_id) REFERENCES public.users(user_id);


--
-- Name: approval_requests approval_requests_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(user_id);


--
-- Name: assessment_components assessment_components_examination_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_components
    ADD CONSTRAINT assessment_components_examination_id_fkey FOREIGN KEY (examination_id) REFERENCES public.examinations(examination_id);


--
-- Name: assessment_components assessment_components_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_components
    ADD CONSTRAINT assessment_components_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.course_offerings(offering_id);


--
-- Name: attendance_sessions attendance_sessions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_sessions
    ADD CONSTRAINT attendance_sessions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: attendance_sessions attendance_sessions_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_sessions
    ADD CONSTRAINT attendance_sessions_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.course_offerings(offering_id);


--
-- Name: attendance_sessions attendance_sessions_time_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_sessions
    ADD CONSTRAINT attendance_sessions_time_slot_id_fkey FOREIGN KEY (time_slot_id) REFERENCES public.time_slots(time_slot_id);


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: batch_section_assignments batch_section_assignments_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_section_assignments
    ADD CONSTRAINT batch_section_assignments_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE;


--
-- Name: batch_section_assignments batch_section_assignments_initial_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_section_assignments
    ADD CONSTRAINT batch_section_assignments_initial_section_id_fkey FOREIGN KEY (initial_section_id) REFERENCES public.sections(section_id) ON DELETE SET NULL;


--
-- Name: batch_section_assignments batch_section_assignments_section_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_section_assignments
    ADD CONSTRAINT batch_section_assignments_section_master_id_fkey FOREIGN KEY (section_master_id) REFERENCES public.section_masters(section_master_id);


--
-- Name: batch_survey_settings batch_survey_settings_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batch_survey_settings
    ADD CONSTRAINT batch_survey_settings_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE;


--
-- Name: building_departments building_departments_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.building_departments
    ADD CONSTRAINT building_departments_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(building_id) ON DELETE CASCADE;


--
-- Name: building_departments building_departments_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.building_departments
    ADD CONSTRAINT building_departments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE CASCADE;


--
-- Name: buildings buildings_campus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buildings
    ADD CONSTRAINT buildings_campus_id_fkey FOREIGN KEY (campus_id) REFERENCES public.campuses(campus_id);


--
-- Name: campuses campuses_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campuses
    ADD CONSTRAINT campuses_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_subject_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_subject_master_id_fkey FOREIGN KEY (subject_master_id) REFERENCES public.subject_masters(subject_master_id);


--
-- Name: class_teacher_allocations class_teacher_allocations_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_teacher_allocations
    ADD CONSTRAINT class_teacher_allocations_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: classroom_facilities classroom_facilities_classroom_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facilities
    ADD CONSTRAINT classroom_facilities_classroom_id_fkey FOREIGN KEY (classroom_id) REFERENCES public.classrooms(classroom_id) ON DELETE CASCADE;


--
-- Name: classroom_facilities classroom_facilities_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_facilities
    ADD CONSTRAINT classroom_facilities_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.classroom_facility_masters(facility_id) ON DELETE RESTRICT;


--
-- Name: classroom_unavailability classroom_unavailability_classroom_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_unavailability
    ADD CONSTRAINT classroom_unavailability_classroom_id_fkey FOREIGN KEY (classroom_id) REFERENCES public.classrooms(classroom_id) ON DELETE CASCADE;


--
-- Name: classroom_unavailability classroom_unavailability_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_unavailability
    ADD CONSTRAINT classroom_unavailability_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: classroom_unavailability classroom_unavailability_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_unavailability
    ADD CONSTRAINT classroom_unavailability_period_id_fkey FOREIGN KEY (period_id) REFERENCES academics.academic_periods(period_id) ON DELETE RESTRICT;


--
-- Name: classroom_unavailability classroom_unavailability_week_day_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classroom_unavailability
    ADD CONSTRAINT classroom_unavailability_week_day_id_fkey FOREIGN KEY (week_day_id) REFERENCES academics.week_days(week_day_id) ON DELETE RESTRICT;


--
-- Name: classrooms classrooms_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(building_id) ON DELETE RESTRICT;


--
-- Name: classrooms classrooms_campus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_campus_id_fkey FOREIGN KEY (campus_id) REFERENCES public.campuses(campus_id) ON DELETE RESTRICT;


--
-- Name: classrooms classrooms_classroom_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_classroom_type_id_fkey FOREIGN KEY (classroom_type_id) REFERENCES public.classroom_types(classroom_type_id) ON DELETE RESTRICT;


--
-- Name: classrooms classrooms_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: classrooms classrooms_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classrooms
    ADD CONSTRAINT classrooms_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: common_master_types common_master_types_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_types
    ADD CONSTRAINT common_master_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: common_master_types common_master_types_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_types
    ADD CONSTRAINT common_master_types_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id);


--
-- Name: common_master_types common_master_types_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_types
    ADD CONSTRAINT common_master_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: common_master_values common_master_values_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values
    ADD CONSTRAINT common_master_values_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: common_master_values common_master_values_master_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values
    ADD CONSTRAINT common_master_values_master_type_id_fkey FOREIGN KEY (master_type_id) REFERENCES public.common_master_types(master_type_id) ON DELETE CASCADE;


--
-- Name: common_master_values common_master_values_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_master_values
    ADD CONSTRAINT common_master_values_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: course_initial_setup course_initial_setup_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_initial_setup
    ADD CONSTRAINT course_initial_setup_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE;


--
-- Name: course_initial_setup course_initial_setup_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_initial_setup
    ADD CONSTRAINT course_initial_setup_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.programmes(programme_id) ON DELETE CASCADE;


--
-- Name: course_initial_setup course_initial_setup_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_initial_setup
    ADD CONSTRAINT course_initial_setup_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id) ON DELETE CASCADE;


--
-- Name: course_offerings course_offerings_curriculum_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_offerings
    ADD CONSTRAINT course_offerings_curriculum_course_id_fkey FOREIGN KEY (curriculum_course_id) REFERENCES public.curriculum_courses(curriculum_course_id);


--
-- Name: course_offerings course_offerings_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_offerings
    ADD CONSTRAINT course_offerings_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: course_offerings course_offerings_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_offerings
    ADD CONSTRAINT course_offerings_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(term_id);


--
-- Name: course_prerequisites course_prerequisites_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_prerequisites
    ADD CONSTRAINT course_prerequisites_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id) ON DELETE CASCADE;


--
-- Name: course_prerequisites course_prerequisites_prerequisite_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_prerequisites
    ADD CONSTRAINT course_prerequisites_prerequisite_course_id_fkey FOREIGN KEY (prerequisite_course_id) REFERENCES public.courses(course_id);


--
-- Name: course_results course_results_grade_scale_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_results
    ADD CONSTRAINT course_results_grade_scale_id_fkey FOREIGN KEY (grade_scale_id) REFERENCES public.grade_scales(grade_scale_id);


--
-- Name: course_results course_results_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_results
    ADD CONSTRAINT course_results_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.course_offerings(offering_id);


--
-- Name: course_results course_results_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_results
    ADD CONSTRAINT course_results_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: courses courses_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: curriculum_courses curriculum_courses_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_courses
    ADD CONSTRAINT curriculum_courses_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: curriculum_courses curriculum_courses_scheme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_courses
    ADD CONSTRAINT curriculum_courses_scheme_id_fkey FOREIGN KEY (scheme_id) REFERENCES public.curriculum_schemes(scheme_id);


--
-- Name: curriculum_courses curriculum_courses_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_courses
    ADD CONSTRAINT curriculum_courses_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: curriculum_schemes curriculum_schemes_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_schemes
    ADD CONSTRAINT curriculum_schemes_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: dashboard_messages dashboard_messages_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_messages
    ADD CONSTRAINT dashboard_messages_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: dashboard_messages dashboard_messages_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_messages
    ADD CONSTRAINT dashboard_messages_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: dashboard_messages dashboard_messages_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_messages
    ADD CONSTRAINT dashboard_messages_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE SET NULL;


--
-- Name: dashboard_messages dashboard_messages_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_messages
    ADD CONSTRAINT dashboard_messages_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: dashboard_notice_acknowledgments dashboard_notice_acknowledgments_notice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_acknowledgments
    ADD CONSTRAINT dashboard_notice_acknowledgments_notice_id_fkey FOREIGN KEY (notice_id) REFERENCES public.dashboard_notices(notice_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_acknowledgments dashboard_notice_acknowledgments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_acknowledgments
    ADD CONSTRAINT dashboard_notice_acknowledgments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_notice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_notice_id_fkey FOREIGN KEY (notice_id) REFERENCES public.dashboard_notices(notice_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE CASCADE;


--
-- Name: dashboard_notice_audiences dashboard_notice_audiences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notice_audiences
    ADD CONSTRAINT dashboard_notice_audiences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: dashboard_notices dashboard_notices_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE SET NULL;


--
-- Name: dashboard_notices dashboard_notices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: dashboard_notices dashboard_notices_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: dashboard_notices dashboard_notices_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE SET NULL;


--
-- Name: dashboard_notices dashboard_notices_published_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_published_by_fkey FOREIGN KEY (published_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: dashboard_notices dashboard_notices_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE SET NULL;


--
-- Name: dashboard_notices dashboard_notices_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_notices
    ADD CONSTRAINT dashboard_notices_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: departments departments_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: employee_leaves employee_leaves_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leaves
    ADD CONSTRAINT employee_leaves_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.employees(employee_id);


--
-- Name: employee_leaves employee_leaves_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leaves
    ADD CONSTRAINT employee_leaves_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: employee_login_history employee_login_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_login_history
    ADD CONSTRAINT employee_login_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: employee_login_history employee_login_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_login_history
    ADD CONSTRAINT employee_login_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id);


--
-- Name: employee_qualifications employee_qualifications_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_qualifications
    ADD CONSTRAINT employee_qualifications_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE CASCADE;


--
-- Name: employees employees_campus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_campus_id_fkey FOREIGN KEY (campus_id) REFERENCES public.campuses(campus_id);


--
-- Name: employees employees_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: employees employees_designation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_designation_id_fkey FOREIGN KEY (designation_id) REFERENCES public.designations(designation_id);


--
-- Name: employees employees_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: employees employees_reporting_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_reporting_employee_id_fkey FOREIGN KEY (reporting_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: employees employees_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: exam_types exam_types_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types
    ADD CONSTRAINT exam_types_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: examinations examinations_exam_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.examinations
    ADD CONSTRAINT examinations_exam_type_id_fkey FOREIGN KEY (exam_type_id) REFERENCES public.exam_types(exam_type_id);


--
-- Name: examinations examinations_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.examinations
    ADD CONSTRAINT examinations_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(term_id);


--
-- Name: faculty_course_allocations faculty_course_allocations_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faculty_course_allocations
    ADD CONSTRAINT faculty_course_allocations_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.employees(employee_id);


--
-- Name: faculty_course_allocations faculty_course_allocations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faculty_course_allocations
    ADD CONSTRAINT faculty_course_allocations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: faculty_course_allocations faculty_course_allocations_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faculty_course_allocations
    ADD CONSTRAINT faculty_course_allocations_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.course_offerings(offering_id) ON DELETE CASCADE;


--
-- Name: fee_heads fee_heads_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_heads
    ADD CONSTRAINT fee_heads_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: fee_payment_allocations fee_payment_allocations_demand_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payment_allocations
    ADD CONSTRAINT fee_payment_allocations_demand_id_fkey FOREIGN KEY (demand_id) REFERENCES public.student_fee_demands(demand_id);


--
-- Name: fee_payment_allocations fee_payment_allocations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payment_allocations
    ADD CONSTRAINT fee_payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.fee_payments(payment_id) ON DELETE CASCADE;


--
-- Name: fee_payments fee_payments_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payments
    ADD CONSTRAINT fee_payments_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(user_id);


--
-- Name: fee_payments fee_payments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_payments
    ADD CONSTRAINT fee_payments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: fee_structure_items fee_structure_items_fee_head_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structure_items
    ADD CONSTRAINT fee_structure_items_fee_head_id_fkey FOREIGN KEY (fee_head_id) REFERENCES public.fee_heads(fee_head_id);


--
-- Name: fee_structure_items fee_structure_items_fee_structure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structure_items
    ADD CONSTRAINT fee_structure_items_fee_structure_id_fkey FOREIGN KEY (fee_structure_id) REFERENCES public.fee_structures(fee_structure_id) ON DELETE CASCADE;


--
-- Name: fee_structure_items fee_structure_items_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structure_items
    ADD CONSTRAINT fee_structure_items_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: fee_structures fee_structures_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structures
    ADD CONSTRAINT fee_structures_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: fee_structures fee_structures_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structures
    ADD CONSTRAINT fee_structures_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: fee_structures fee_structures_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fee_structures
    ADD CONSTRAINT fee_structures_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: file_attachments file_attachments_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file_attachments
    ADD CONSTRAINT file_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(user_id);


--
-- Name: departments fk_department_hod; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_department_hod FOREIGN KEY (hod_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: sections fk_section_coordinator; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT fk_section_coordinator FOREIGN KEY (class_coordinator_id) REFERENCES public.employees(employee_id);


--
-- Name: grade_scales grade_scales_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales
    ADD CONSTRAINT grade_scales_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: grievance_actions grievance_actions_action_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievance_actions
    ADD CONSTRAINT grievance_actions_action_by_fkey FOREIGN KEY (action_by) REFERENCES public.users(user_id);


--
-- Name: grievance_actions grievance_actions_grievance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievance_actions
    ADD CONSTRAINT grievance_actions_grievance_id_fkey FOREIGN KEY (grievance_id) REFERENCES public.grievances(grievance_id) ON DELETE CASCADE;


--
-- Name: grievances grievances_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievances
    ADD CONSTRAINT grievances_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(user_id);


--
-- Name: grievances grievances_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grievances
    ADD CONSTRAINT grievances_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.users(user_id);


--
-- Name: hostel_allocations hostel_allocations_hostel_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_allocations
    ADD CONSTRAINT hostel_allocations_hostel_room_id_fkey FOREIGN KEY (hostel_room_id) REFERENCES public.hostel_rooms(hostel_room_id);


--
-- Name: hostel_allocations hostel_allocations_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_allocations
    ADD CONSTRAINT hostel_allocations_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: hostel_rooms hostel_rooms_hostel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostel_rooms
    ADD CONSTRAINT hostel_rooms_hostel_id_fkey FOREIGN KEY (hostel_id) REFERENCES public.hostels(hostel_id);


--
-- Name: hostels hostels_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostels
    ADD CONSTRAINT hostels_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: hostels hostels_warden_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hostels
    ADD CONSTRAINT hostels_warden_employee_id_fkey FOREIGN KEY (warden_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: issue_followups issue_followups_student_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_followups
    ADD CONSTRAINT issue_followups_student_issue_id_fkey FOREIGN KEY (student_issue_id) REFERENCES public.student_issues(student_issue_id) ON DELETE CASCADE;


--
-- Name: issue_followups issue_followups_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_followups
    ADD CONSTRAINT issue_followups_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: libraries libraries_campus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.libraries
    ADD CONSTRAINT libraries_campus_id_fkey FOREIGN KEY (campus_id) REFERENCES public.campuses(campus_id) ON DELETE SET NULL;


--
-- Name: libraries libraries_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.libraries
    ADD CONSTRAINT libraries_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: library_almiras library_almiras_library_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_almiras
    ADD CONSTRAINT library_almiras_library_id_fkey FOREIGN KEY (library_id) REFERENCES public.libraries(library_id) ON DELETE CASCADE;


--
-- Name: library_almiras library_almiras_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_almiras
    ADD CONSTRAINT library_almiras_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(room_id) ON DELETE SET NULL;


--
-- Name: library_authors library_authors_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_authors
    ADD CONSTRAINT library_authors_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_authors library_authors_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_authors
    ADD CONSTRAINT library_authors_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_book_copies library_book_copies_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_copies
    ADD CONSTRAINT library_book_copies_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.library_books(book_id) ON DELETE CASCADE;


--
-- Name: library_book_issues library_book_issues_book_copy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_issues
    ADD CONSTRAINT library_book_issues_book_copy_id_fkey FOREIGN KEY (book_copy_id) REFERENCES public.library_book_copies(book_copy_id);


--
-- Name: library_book_issues library_book_issues_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_issues
    ADD CONSTRAINT library_book_issues_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_book_issues library_book_issues_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_issues
    ADD CONSTRAINT library_book_issues_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: library_book_issues library_book_issues_issue_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_issues
    ADD CONSTRAINT library_book_issues_issue_type_id_fkey FOREIGN KEY (issue_type_id) REFERENCES public.library_issue_types(issue_type_id);


--
-- Name: library_book_stock library_book_stock_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_book_stock
    ADD CONSTRAINT library_book_stock_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.library_books(book_id) ON DELETE CASCADE;


--
-- Name: library_books library_books_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.library_authors(author_id);


--
-- Name: library_books library_books_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.library_categories(category_id);


--
-- Name: library_books library_books_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_books library_books_publisher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_publisher_id_fkey FOREIGN KEY (publisher_id) REFERENCES public.library_publishers(publisher_id);


--
-- Name: library_books library_books_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.library_subjects(subject_id);


--
-- Name: library_books library_books_title_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_title_id_fkey FOREIGN KEY (title_id) REFERENCES public.library_titles(title_id);


--
-- Name: library_books library_books_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_books
    ADD CONSTRAINT library_books_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_categories library_categories_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories
    ADD CONSTRAINT library_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_categories library_categories_parent_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories
    ADD CONSTRAINT library_categories_parent_category_id_fkey FOREIGN KEY (parent_category_id) REFERENCES public.library_categories(category_id) ON DELETE SET NULL;


--
-- Name: library_categories library_categories_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_categories
    ADD CONSTRAINT library_categories_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_issue_types library_issue_types_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_issue_types
    ADD CONSTRAINT library_issue_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_issue_types library_issue_types_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_issue_types
    ADD CONSTRAINT library_issue_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_members library_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_members
    ADD CONSTRAINT library_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: library_publishers library_publishers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_publishers
    ADD CONSTRAINT library_publishers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_publishers library_publishers_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_publishers
    ADD CONSTRAINT library_publishers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_purchase_invoice_items library_purchase_invoice_items_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoice_items
    ADD CONSTRAINT library_purchase_invoice_items_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.library_books(book_id);


--
-- Name: library_purchase_invoice_items library_purchase_invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoice_items
    ADD CONSTRAINT library_purchase_invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.library_purchase_invoices(invoice_id) ON DELETE CASCADE;


--
-- Name: library_purchase_invoices library_purchase_invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices
    ADD CONSTRAINT library_purchase_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_purchase_invoices library_purchase_invoices_posted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices
    ADD CONSTRAINT library_purchase_invoices_posted_by_fkey FOREIGN KEY (posted_by) REFERENCES public.users(user_id);


--
-- Name: library_purchase_invoices library_purchase_invoices_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices
    ADD CONSTRAINT library_purchase_invoices_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.library_purchase_orders(purchase_order_id);


--
-- Name: library_purchase_invoices library_purchase_invoices_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_invoices
    ADD CONSTRAINT library_purchase_invoices_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.library_suppliers(supplier_id);


--
-- Name: library_purchase_order_items library_purchase_order_items_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_order_items
    ADD CONSTRAINT library_purchase_order_items_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.library_books(book_id);


--
-- Name: library_purchase_order_items library_purchase_order_items_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_order_items
    ADD CONSTRAINT library_purchase_order_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.library_purchase_orders(purchase_order_id) ON DELETE CASCADE;


--
-- Name: library_purchase_orders library_purchase_orders_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_orders
    ADD CONSTRAINT library_purchase_orders_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(user_id);


--
-- Name: library_purchase_orders library_purchase_orders_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_orders
    ADD CONSTRAINT library_purchase_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_purchase_orders library_purchase_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_purchase_orders
    ADD CONSTRAINT library_purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.library_suppliers(supplier_id);


--
-- Name: library_student_members library_student_members_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_student_members
    ADD CONSTRAINT library_student_members_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: library_study_material_issues library_study_material_issues_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_issues
    ADD CONSTRAINT library_study_material_issues_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_study_material_issues library_study_material_issues_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_issues
    ADD CONSTRAINT library_study_material_issues_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: library_study_material_issues library_study_material_issues_study_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_issues
    ADD CONSTRAINT library_study_material_issues_study_material_id_fkey FOREIGN KEY (study_material_id) REFERENCES public.library_study_materials(study_material_id);


--
-- Name: library_study_material_prices library_study_material_prices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_prices
    ADD CONSTRAINT library_study_material_prices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_study_material_prices library_study_material_prices_study_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_prices
    ADD CONSTRAINT library_study_material_prices_study_material_id_fkey FOREIGN KEY (study_material_id) REFERENCES public.library_study_materials(study_material_id);


--
-- Name: library_study_material_prices library_study_material_prices_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_material_prices
    ADD CONSTRAINT library_study_material_prices_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_study_materials library_study_materials_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: library_study_materials library_study_materials_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_study_materials library_study_materials_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.library_subjects(subject_id);


--
-- Name: library_study_materials library_study_materials_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_study_materials
    ADD CONSTRAINT library_study_materials_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_subjects library_subjects_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects
    ADD CONSTRAINT library_subjects_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_subjects library_subjects_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects
    ADD CONSTRAINT library_subjects_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: library_subjects library_subjects_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_subjects
    ADD CONSTRAINT library_subjects_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_suppliers library_suppliers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_suppliers
    ADD CONSTRAINT library_suppliers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_suppliers library_suppliers_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_suppliers
    ADD CONSTRAINT library_suppliers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_titles library_titles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_titles
    ADD CONSTRAINT library_titles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: library_titles library_titles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_titles
    ADD CONSTRAINT library_titles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: library_transactions library_transactions_book_copy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_transactions
    ADD CONSTRAINT library_transactions_book_copy_id_fkey FOREIGN KEY (book_copy_id) REFERENCES public.library_book_copies(book_copy_id);


--
-- Name: library_transactions library_transactions_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_transactions
    ADD CONSTRAINT library_transactions_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.users(user_id);


--
-- Name: library_transactions library_transactions_library_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_transactions
    ADD CONSTRAINT library_transactions_library_member_id_fkey FOREIGN KEY (library_member_id) REFERENCES public.library_members(library_member_id);


--
-- Name: library_transactions library_transactions_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_transactions
    ADD CONSTRAINT library_transactions_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(user_id);


--
-- Name: login_history login_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history
    ADD CONSTRAINT login_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: login_logs login_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_logs
    ADD CONSTRAINT login_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: mentor_assignments mentor_assignments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_assignments
    ADD CONSTRAINT mentor_assignments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: mentor_assignments mentor_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_assignments
    ADD CONSTRAINT mentor_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: mentor_assignments mentor_assignments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_assignments
    ADD CONSTRAINT mentor_assignments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: mentor_meetings mentor_meetings_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_meetings
    ADD CONSTRAINT mentor_meetings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.employees(employee_id);


--
-- Name: mentor_meetings mentor_meetings_mentor_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentor_meetings
    ADD CONSTRAINT mentor_meetings_mentor_assignment_id_fkey FOREIGN KEY (mentor_assignment_id) REFERENCES public.mentor_assignments(mentor_assignment_id);


--
-- Name: mentoring_topics mentoring_topics_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentoring_topics
    ADD CONSTRAINT mentoring_topics_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: mentoring_topics mentoring_topics_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mentoring_topics
    ADD CONSTRAINT mentoring_topics_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: notices notices_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: notices notices_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: notices notices_published_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_published_by_fkey FOREIGN KEY (published_by) REFERENCES public.users(user_id);


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: password_reset_history password_reset_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_history
    ADD CONSTRAINT password_reset_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id);


--
-- Name: permission_change_history permission_change_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history
    ADD CONSTRAINT permission_change_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.user_accounts(user_id);


--
-- Name: permission_change_history permission_change_history_menu_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history
    ADD CONSTRAINT permission_change_history_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES public.system_menus(menu_id);


--
-- Name: permission_change_history permission_change_history_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history
    ADD CONSTRAINT permission_change_history_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id);


--
-- Name: permission_change_history permission_change_history_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history
    ADD CONSTRAINT permission_change_history_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id);


--
-- Name: permission_change_history permission_change_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_change_history
    ADD CONSTRAINT permission_change_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id);


--
-- Name: preferred_books preferred_books_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preferred_books
    ADD CONSTRAINT preferred_books_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: preferred_books preferred_books_subject_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preferred_books
    ADD CONSTRAINT preferred_books_subject_master_id_fkey FOREIGN KEY (subject_master_id) REFERENCES public.subject_masters(subject_master_id);


--
-- Name: preferred_books preferred_books_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preferred_books
    ADD CONSTRAINT preferred_books_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: programme_section_merges programme_section_merges_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges
    ADD CONSTRAINT programme_section_merges_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: programme_section_merges programme_section_merges_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges
    ADD CONSTRAINT programme_section_merges_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: programme_section_merges programme_section_merges_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges
    ADD CONSTRAINT programme_section_merges_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: programme_section_merges programme_section_merges_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges
    ADD CONSTRAINT programme_section_merges_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: programme_section_merges programme_section_merges_target_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_section_merges
    ADD CONSTRAINT programme_section_merges_target_section_id_fkey FOREIGN KEY (target_section_id) REFERENCES public.sections(section_id);


--
-- Name: programme_semester_definitions programme_semester_definitions_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT programme_semester_definitions_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.programmes(programme_id);


--
-- Name: programme_semester_definitions programme_semester_definitions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT programme_semester_definitions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: programme_semester_definitions programme_semester_definitions_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT programme_semester_definitions_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: programme_semester_definitions programme_semester_definitions_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT programme_semester_definitions_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: programme_semester_definitions programme_semester_definitions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programme_semester_definitions
    ADD CONSTRAINT programme_semester_definitions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: programmes programmes_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.programmes
    ADD CONSTRAINT programmes_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: prospective_student_followups prospective_student_followups_followed_up_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_followups
    ADD CONSTRAINT prospective_student_followups_followed_up_by_fkey FOREIGN KEY (followed_up_by) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: prospective_student_followups prospective_student_followups_prospective_student_mentor_a_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_followups
    ADD CONSTRAINT prospective_student_followups_prospective_student_mentor_a_fkey FOREIGN KEY (prospective_student_mentor_allotment_id) REFERENCES public.prospective_student_mentor_allotments(prospective_student_mentor_allotment_id) ON DELETE CASCADE;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotmen_prospective_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotmen_prospective_student_id_fkey FOREIGN KEY (prospective_student_id) REFERENCES public.prospective_students(prospective_student_id) ON DELETE CASCADE;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_mentor_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_mentor_employee_id_fkey FOREIGN KEY (mentor_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: prospective_student_mentor_allotments prospective_student_mentor_allotments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_student_mentor_allotments
    ADD CONSTRAINT prospective_student_mentor_allotments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_admission_status_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_admission_status_value_id_fkey FOREIGN KEY (admission_status_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_converted_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_converted_student_id_fkey FOREIGN KEY (converted_student_id) REFERENCES public.students(student_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: prospective_students prospective_students_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE SET NULL;


--
-- Name: prospective_students prospective_students_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prospective_students
    ADD CONSTRAINT prospective_students_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: reviewer_allotment_mentors reviewer_allotment_mentors_mentor_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviewer_allotment_mentors
    ADD CONSTRAINT reviewer_allotment_mentors_mentor_employee_id_fkey FOREIGN KEY (mentor_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: reviewer_allotment_mentors reviewer_allotment_mentors_student_reviewer_allotment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviewer_allotment_mentors
    ADD CONSTRAINT reviewer_allotment_mentors_student_reviewer_allotment_id_fkey FOREIGN KEY (student_reviewer_allotment_id) REFERENCES public.student_reviewer_allotments(student_reviewer_allotment_id) ON DELETE CASCADE;


--
-- Name: reviewer_allotment_students reviewer_allotment_students_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviewer_allotment_students
    ADD CONSTRAINT reviewer_allotment_students_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: reviewer_allotment_students reviewer_allotment_students_student_reviewer_allotment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviewer_allotment_students
    ADD CONSTRAINT reviewer_allotment_students_student_reviewer_allotment_id_fkey FOREIGN KEY (student_reviewer_allotment_id) REFERENCES public.student_reviewer_allotments(student_reviewer_allotment_id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: rooms rooms_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(building_id);


--
-- Name: route_vehicle_assignments route_vehicle_assignments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_vehicle_assignments
    ADD CONSTRAINT route_vehicle_assignments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: route_vehicle_assignments route_vehicle_assignments_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_vehicle_assignments
    ADD CONSTRAINT route_vehicle_assignments_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.transport_routes(route_id);


--
-- Name: route_vehicle_assignments route_vehicle_assignments_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_vehicle_assignments
    ADD CONSTRAINT route_vehicle_assignments_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(vehicle_id);


--
-- Name: section_definitions section_definitions_admission_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_definitions
    ADD CONSTRAINT section_definitions_admission_course_id_fkey FOREIGN KEY (admission_course_id) REFERENCES public.programmes(programme_id);


--
-- Name: section_definitions section_definitions_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_definitions
    ADD CONSTRAINT section_definitions_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.programmes(programme_id);


--
-- Name: section_definitions section_definitions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_definitions
    ADD CONSTRAINT section_definitions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: section_definitions section_definitions_section_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_definitions
    ADD CONSTRAINT section_definitions_section_master_id_fkey FOREIGN KEY (section_master_id) REFERENCES public.section_masters(section_master_id);


--
-- Name: section_masters section_masters_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_masters
    ADD CONSTRAINT section_masters_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: section_masters section_masters_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_masters
    ADD CONSTRAINT section_masters_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: section_merge_groups section_merge_groups_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_merge_groups
    ADD CONSTRAINT section_merge_groups_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: section_merge_groups section_merge_groups_first_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_merge_groups
    ADD CONSTRAINT section_merge_groups_first_section_id_fkey FOREIGN KEY (first_section_id) REFERENCES public.sections(section_id);


--
-- Name: section_merge_groups section_merge_groups_second_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_merge_groups
    ADD CONSTRAINT section_merge_groups_second_section_id_fkey FOREIGN KEY (second_section_id) REFERENCES public.sections(section_id);


--
-- Name: section_merge_groups section_merge_groups_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.section_merge_groups
    ADD CONSTRAINT section_merge_groups_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: sections sections_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: sections sections_section_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_section_master_id_fkey FOREIGN KEY (section_master_id) REFERENCES public.section_masters(section_master_id) ON DELETE SET NULL;


--
-- Name: sections sections_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: sections sections_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(term_id);


--
-- Name: semester_results semester_results_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semester_results
    ADD CONSTRAINT semester_results_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: semester_results semester_results_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semester_results
    ADD CONSTRAINT semester_results_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: semester_results semester_results_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semester_results
    ADD CONSTRAINT semester_results_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(term_id);


--
-- Name: semesters semesters_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: student_academic_history student_academic_history_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_academic_history
    ADD CONSTRAINT student_academic_history_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_addresses student_addresses_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_addresses
    ADD CONSTRAINT student_addresses_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_attendance student_attendance_attendance_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance
    ADD CONSTRAINT student_attendance_attendance_session_id_fkey FOREIGN KEY (attendance_session_id) REFERENCES public.attendance_sessions(attendance_session_id) ON DELETE CASCADE;


--
-- Name: student_attendance_entries student_attendance_entries_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entries
    ADD CONSTRAINT student_attendance_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: student_attendance_entries student_attendance_entries_subject_teacher_allocation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entries
    ADD CONSTRAINT student_attendance_entries_subject_teacher_allocation_id_fkey FOREIGN KEY (subject_teacher_allocation_id) REFERENCES public.subject_teacher_allocations(subject_teacher_allocation_id);


--
-- Name: student_attendance_entry_students student_attendance_entry_students_attendance_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entry_students
    ADD CONSTRAINT student_attendance_entry_students_attendance_entry_id_fkey FOREIGN KEY (attendance_entry_id) REFERENCES public.student_attendance_entries(attendance_entry_id) ON DELETE CASCADE;


--
-- Name: student_attendance_entry_students student_attendance_entry_students_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entry_students
    ADD CONSTRAINT student_attendance_entry_students_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: student_attendance_entry_students student_attendance_entry_students_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance_entry_students
    ADD CONSTRAINT student_attendance_entry_students_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_attendance student_attendance_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_attendance
    ADD CONSTRAINT student_attendance_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_branches student_branches_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_branches
    ADD CONSTRAINT student_branches_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: student_branches student_branches_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_branches
    ADD CONSTRAINT student_branches_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: student_course_registrations student_course_registrations_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_course_registrations
    ADD CONSTRAINT student_course_registrations_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.course_offerings(offering_id);


--
-- Name: student_course_registrations student_course_registrations_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_course_registrations
    ADD CONSTRAINT student_course_registrations_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_documents student_documents_document_type_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_document_type_value_id_fkey FOREIGN KEY (document_type_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: student_documents student_documents_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_documents student_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_documents student_documents_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.employees(employee_id);


--
-- Name: student_fee_demands student_fee_demands_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_demands
    ADD CONSTRAINT student_fee_demands_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: student_fee_demands student_fee_demands_fee_head_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_demands
    ADD CONSTRAINT student_fee_demands_fee_head_id_fkey FOREIGN KEY (fee_head_id) REFERENCES public.fee_heads(fee_head_id);


--
-- Name: student_fee_demands student_fee_demands_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_demands
    ADD CONSTRAINT student_fee_demands_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_fee_demands student_fee_demands_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_demands
    ADD CONSTRAINT student_fee_demands_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(term_id);


--
-- Name: student_fee_undertakings student_fee_undertakings_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE SET NULL;


--
-- Name: student_fee_undertakings student_fee_undertakings_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_fee_undertakings student_fee_undertakings_fee_category_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_fee_category_value_id_fkey FOREIGN KEY (fee_category_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: student_fee_undertakings student_fee_undertakings_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: student_fee_undertakings student_fee_undertakings_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: student_fee_undertakings student_fee_undertakings_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_fee_undertakings student_fee_undertakings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_fee_undertakings student_fee_undertakings_witness_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_fee_undertakings
    ADD CONSTRAINT student_fee_undertakings_witness_employee_id_fkey FOREIGN KEY (witness_employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: student_guardians student_guardians_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardians
    ADD CONSTRAINT student_guardians_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardians(guardian_id) ON DELETE CASCADE;


--
-- Name: student_guardians student_guardians_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardians
    ADD CONSTRAINT student_guardians_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_import_batches student_import_batches_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_import_batches
    ADD CONSTRAINT student_import_batches_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE SET NULL;


--
-- Name: student_import_batches student_import_batches_imported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_import_batches
    ADD CONSTRAINT student_import_batches_imported_by_fkey FOREIGN KEY (imported_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_import_batches student_import_batches_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_import_batches
    ADD CONSTRAINT student_import_batches_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: student_issues student_issues_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_issues
    ADD CONSTRAINT student_issues_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.employees(employee_id);


--
-- Name: student_issues student_issues_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_issues
    ADD CONSTRAINT student_issues_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.users(user_id);


--
-- Name: student_issues student_issues_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_issues
    ADD CONSTRAINT student_issues_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_login_actions student_login_actions_action_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_login_actions
    ADD CONSTRAINT student_login_actions_action_by_fkey FOREIGN KEY (action_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_login_actions student_login_actions_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_login_actions
    ADD CONSTRAINT student_login_actions_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_login_actions student_login_actions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_login_actions
    ADD CONSTRAINT student_login_actions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_marks student_marks_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment_components(assessment_id) ON DELETE CASCADE;


--
-- Name: student_marks student_marks_entered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.employees(employee_id);


--
-- Name: student_marks student_marks_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_marks student_marks_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.employees(employee_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentor_allotments student_mentor_allotments_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: student_mentor_allotments student_mentor_allotments_mentor_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_mentor_employee_id_fkey FOREIGN KEY (mentor_id) REFERENCES public.employees(employee_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_programme_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_programme_batch_id_fkey FOREIGN KEY (programme_batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_programme_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_programme_section_id_fkey FOREIGN KEY (programme_section_id) REFERENCES public.sections(section_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: student_mentor_allotments student_mentor_allotments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_mentor_allotments student_mentor_allotments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_allotments
    ADD CONSTRAINT student_mentor_allotments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentor_transfer_history student_mentor_transfer_histor_previous_mentor_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_transfer_history
    ADD CONSTRAINT student_mentor_transfer_histor_previous_mentor_employee_id_fkey FOREIGN KEY (previous_mentor_employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: student_mentor_transfer_history student_mentor_transfer_history_new_mentor_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_transfer_history
    ADD CONSTRAINT student_mentor_transfer_history_new_mentor_employee_id_fkey FOREIGN KEY (new_mentor_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: student_mentor_transfer_history student_mentor_transfer_history_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_transfer_history
    ADD CONSTRAINT student_mentor_transfer_history_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_mentor_transfer_history student_mentor_transfer_history_transferred_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentor_transfer_history
    ADD CONSTRAINT student_mentor_transfer_history_transferred_by_fkey FOREIGN KEY (transferred_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_attachments student_mentoring_attachments_student_fee_undertaking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_attachments
    ADD CONSTRAINT student_mentoring_attachments_student_fee_undertaking_id_fkey FOREIGN KEY (student_fee_undertaking_id) REFERENCES public.student_fee_undertakings(student_fee_undertaking_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_attachments student_mentoring_attachments_student_mentoring_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_attachments
    ADD CONSTRAINT student_mentoring_attachments_student_mentoring_session_id_fkey FOREIGN KEY (student_mentoring_session_id) REFERENCES public.student_mentoring_sessions(student_mentoring_session_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_attachments student_mentoring_attachments_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_attachments
    ADD CONSTRAINT student_mentoring_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_followups student_mentoring_followups_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_followups
    ADD CONSTRAINT student_mentoring_followups_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_followups student_mentoring_followups_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_followups
    ADD CONSTRAINT student_mentoring_followups_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_followups student_mentoring_followups_student_mentoring_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_followups
    ADD CONSTRAINT student_mentoring_followups_student_mentoring_session_id_fkey FOREIGN KEY (student_mentoring_session_id) REFERENCES public.student_mentoring_sessions(student_mentoring_session_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_reviews student_mentoring_reviews_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews
    ADD CONSTRAINT student_mentoring_reviews_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_reviews student_mentoring_reviews_reviewer_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews
    ADD CONSTRAINT student_mentoring_reviews_reviewer_employee_id_fkey FOREIGN KEY (reviewer_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: student_mentoring_reviews student_mentoring_reviews_student_mentoring_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews
    ADD CONSTRAINT student_mentoring_reviews_student_mentoring_session_id_fkey FOREIGN KEY (student_mentoring_session_id) REFERENCES public.student_mentoring_sessions(student_mentoring_session_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_reviews student_mentoring_reviews_student_reviewer_allotment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_reviews
    ADD CONSTRAINT student_mentoring_reviews_student_reviewer_allotment_id_fkey FOREIGN KEY (student_reviewer_allotment_id) REFERENCES public.student_reviewer_allotments(student_reviewer_allotment_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_session_topics student_mentoring_session_top_student_mentoring_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_session_topics
    ADD CONSTRAINT student_mentoring_session_top_student_mentoring_session_id_fkey FOREIGN KEY (student_mentoring_session_id) REFERENCES public.student_mentoring_sessions(student_mentoring_session_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_session_topics student_mentoring_session_topics_mentoring_topic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_session_topics
    ADD CONSTRAINT student_mentoring_session_topics_mentoring_topic_id_fkey FOREIGN KEY (mentoring_topic_id) REFERENCES public.mentoring_topics(mentoring_topic_id);


--
-- Name: student_mentoring_sessions student_mentoring_sessions_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_mentor_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_mentor_employee_id_fkey FOREIGN KEY (mentor_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: student_mentoring_sessions student_mentoring_sessions_referred_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_referred_department_id_fkey FOREIGN KEY (referred_department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_referred_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_referred_employee_id_fkey FOREIGN KEY (referred_employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_student_mentor_allotment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_student_mentor_allotment_id_fkey FOREIGN KEY (student_mentor_allotment_id) REFERENCES public.student_mentor_allotments(mentor_allotment_id) ON DELETE SET NULL;


--
-- Name: student_mentoring_sessions student_mentoring_sessions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_mentoring_sessions
    ADD CONSTRAINT student_mentoring_sessions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_parents student_parents_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_password_reset_audit student_password_reset_audit_reset_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_password_reset_audit
    ADD CONSTRAINT student_password_reset_audit_reset_by_fkey FOREIGN KEY (reset_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_password_reset_audit student_password_reset_audit_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_password_reset_audit
    ADD CONSTRAINT student_password_reset_audit_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_password_reset_audit student_password_reset_audit_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_password_reset_audit
    ADD CONSTRAINT student_password_reset_audit_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_registration_history student_registration_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_registration_history
    ADD CONSTRAINT student_registration_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_registration_history student_registration_history_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_registration_history
    ADD CONSTRAINT student_registration_history_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_restore_history student_restore_history_previous_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_restore_history
    ADD CONSTRAINT student_restore_history_previous_status_id_fkey FOREIGN KEY (previous_status_id) REFERENCES public.student_statuses(student_status_id) ON DELETE SET NULL;


--
-- Name: student_restore_history student_restore_history_restored_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_restore_history
    ADD CONSTRAINT student_restore_history_restored_by_fkey FOREIGN KEY (restored_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_restore_history student_restore_history_restored_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_restore_history
    ADD CONSTRAINT student_restore_history_restored_status_id_fkey FOREIGN KEY (restored_status_id) REFERENCES public.student_statuses(student_status_id) ON DELETE SET NULL;


--
-- Name: student_restore_history student_restore_history_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_restore_history
    ADD CONSTRAINT student_restore_history_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_reviewer_allotments student_reviewer_allotments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: student_reviewer_allotments student_reviewer_allotments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_reviewer_allotments student_reviewer_allotments_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: student_reviewer_allotments student_reviewer_allotments_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: student_reviewer_allotments student_reviewer_allotments_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id) ON DELETE SET NULL;


--
-- Name: student_reviewer_allotments student_reviewer_allotments_reviewer_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_reviewer_employee_id_fkey FOREIGN KEY (reviewer_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: student_reviewer_allotments student_reviewer_allotments_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE SET NULL;


--
-- Name: student_reviewer_allotments student_reviewer_allotments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_reviewer_allotments
    ADD CONSTRAINT student_reviewer_allotments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_scholarships student_scholarships_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_scholarships
    ADD CONSTRAINT student_scholarships_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: student_scholarships student_scholarships_scholarship_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_scholarships
    ADD CONSTRAINT student_scholarships_scholarship_id_fkey FOREIGN KEY (scholarship_id) REFERENCES public.scholarships(scholarship_id);


--
-- Name: student_scholarships student_scholarships_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_scholarships
    ADD CONSTRAINT student_scholarships_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_section_history student_section_history_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_section_history
    ADD CONSTRAINT student_section_history_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: student_section_history student_section_history_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_section_history
    ADD CONSTRAINT student_section_history_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_status_history student_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_status_history
    ADD CONSTRAINT student_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_status_history student_status_history_new_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_status_history
    ADD CONSTRAINT student_status_history_new_status_id_fkey FOREIGN KEY (new_status_id) REFERENCES public.student_statuses(student_status_id);


--
-- Name: student_status_history student_status_history_old_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_status_history
    ADD CONSTRAINT student_status_history_old_status_id_fkey FOREIGN KEY (old_status_id) REFERENCES public.student_statuses(student_status_id) ON DELETE SET NULL;


--
-- Name: student_status_history student_status_history_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_status_history
    ADD CONSTRAINT student_status_history_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: student_statuses student_statuses_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses
    ADD CONSTRAINT student_statuses_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_statuses student_statuses_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses
    ADD CONSTRAINT student_statuses_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: student_statuses student_statuses_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_statuses
    ADD CONSTRAINT student_statuses_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: student_transport_allocations student_transport_allocations_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations
    ADD CONSTRAINT student_transport_allocations_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: student_transport_allocations student_transport_allocations_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations
    ADD CONSTRAINT student_transport_allocations_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.transport_routes(route_id);


--
-- Name: student_transport_allocations student_transport_allocations_stop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations
    ADD CONSTRAINT student_transport_allocations_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES public.transport_stops(stop_id);


--
-- Name: student_transport_allocations student_transport_allocations_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_transport_allocations
    ADD CONSTRAINT student_transport_allocations_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: students students_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id) ON DELETE SET NULL;


--
-- Name: students students_admission_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_admission_category_id_fkey FOREIGN KEY (admission_category_id) REFERENCES public.admission_categories(admission_category_id) ON DELETE SET NULL;


--
-- Name: students students_admission_type_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_admission_type_value_id_fkey FOREIGN KEY (admission_type_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: students students_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: students students_blood_group_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_blood_group_value_id_fkey FOREIGN KEY (blood_group_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: students students_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.student_branches(branch_id);


--
-- Name: students students_campus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_campus_id_fkey FOREIGN KEY (campus_id) REFERENCES public.campuses(campus_id) ON DELETE SET NULL;


--
-- Name: students students_category_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_category_value_id_fkey FOREIGN KEY (category_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: students students_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: students students_deleted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: students students_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id) ON DELETE SET NULL;


--
-- Name: students students_gender_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_gender_value_id_fkey FOREIGN KEY (gender_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: students students_institute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_institute_id_fkey FOREIGN KEY (institute_id) REFERENCES public.institutions(institution_id) ON DELETE CASCADE;


--
-- Name: students students_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: students students_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: students students_religion_value_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_religion_value_id_fkey FOREIGN KEY (religion_value_id) REFERENCES public.common_master_values(master_value_id) ON DELETE SET NULL;


--
-- Name: students students_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: students students_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id) ON DELETE SET NULL;


--
-- Name: students students_student_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_student_status_id_fkey FOREIGN KEY (student_status_id) REFERENCES public.student_statuses(student_status_id) ON DELETE SET NULL;


--
-- Name: students students_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: students students_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: subject_components subject_components_subject_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_components
    ADD CONSTRAINT subject_components_subject_master_id_fkey FOREIGN KEY (subject_master_id) REFERENCES public.subject_masters(subject_master_id) ON DELETE CASCADE;


--
-- Name: subject_masters subject_masters_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_masters
    ADD CONSTRAINT subject_masters_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: subject_masters subject_masters_programme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_masters
    ADD CONSTRAINT subject_masters_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES public.programmes(programme_id);


--
-- Name: subject_masters subject_masters_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_masters
    ADD CONSTRAINT subject_masters_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: subject_masters subject_masters_semester_programme_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_masters
    ADD CONSTRAINT subject_masters_semester_programme_fk FOREIGN KEY (semester_id, programme_id) REFERENCES public.semesters(semester_id, programme_id) NOT VALID;


--
-- Name: subject_teacher_allocations subject_teacher_allocations_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(academic_year_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.admission_batches(batch_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(section_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(semester_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_subject_master_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_subject_master_id_fkey FOREIGN KEY (subject_master_id) REFERENCES public.subject_masters(subject_master_id);


--
-- Name: subject_teacher_allocations subject_teacher_allocations_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_teacher_allocations
    ADD CONSTRAINT subject_teacher_allocations_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocation_subject_teacher_allocation_i_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocation_subject_teacher_allocation_i_fkey FOREIGN KEY (subject_teacher_allocation_id) REFERENCES public.subject_teacher_allocations(subject_teacher_allocation_id) ON DELETE CASCADE;


--
-- Name: substitute_teacher_allocations substitute_teacher_allocations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocations_original_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocations_original_employee_id_fkey FOREIGN KEY (original_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocations_substitute_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocations_substitute_employee_id_fkey FOREIGN KEY (substitute_employee_id) REFERENCES public.employees(employee_id);


--
-- Name: substitute_teacher_allocations substitute_teacher_allocations_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substitute_teacher_allocations
    ADD CONSTRAINT substitute_teacher_allocations_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: system_menus system_menus_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_menus
    ADD CONSTRAINT system_menus_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.system_modules(module_id) ON DELETE CASCADE;


--
-- Name: system_menus system_menus_parent_menu_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_menus
    ADD CONSTRAINT system_menus_parent_menu_id_fkey FOREIGN KEY (parent_menu_id) REFERENCES public.system_menus(menu_id) ON DELETE CASCADE;


--
-- Name: system_settings system_settings_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: system_settings system_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: time_slots time_slots_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_slots
    ADD CONSTRAINT time_slots_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: timetable_entries timetable_entries_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_entries
    ADD CONSTRAINT timetable_entries_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id);


--
-- Name: timetable_entries timetable_entries_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_entries
    ADD CONSTRAINT timetable_entries_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.course_offerings(offering_id);


--
-- Name: timetable_entries timetable_entries_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_entries
    ADD CONSTRAINT timetable_entries_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(room_id);


--
-- Name: timetable_entries timetable_entries_time_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_entries
    ADD CONSTRAINT timetable_entries_time_slot_id_fkey FOREIGN KEY (time_slot_id) REFERENCES public.time_slots(time_slot_id);


--
-- Name: transport_routes transport_routes_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_routes
    ADD CONSTRAINT transport_routes_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: transport_stops transport_stops_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_stops
    ADD CONSTRAINT transport_stops_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.transport_routes(route_id) ON DELETE CASCADE;


--
-- Name: user_accounts user_accounts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.user_accounts(user_id);


--
-- Name: user_permissions user_permissions_menu_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES public.system_menus(menu_id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id) ON DELETE CASCADE;


--
-- Name: user_photos user_photos_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_photos
    ADD CONSTRAINT user_photos_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: user_photos user_photos_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_photos
    ADD CONSTRAINT user_photos_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(user_id);


--
-- Name: user_roles user_roles_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(department_id);


--
-- Name: user_roles user_roles_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: user_status_history user_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_status_history
    ADD CONSTRAINT user_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: user_status_history user_status_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_status_history
    ADD CONSTRAINT user_status_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: users users_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: users users_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;


--
-- Name: users users_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE SET NULL;


--
-- Name: users users_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: users users_user_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_user_type_id_fkey FOREIGN KEY (user_type_id) REFERENCES public.user_types(user_type_id) ON DELETE RESTRICT;


--
-- Name: vehicles vehicles_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- PostgreSQL database dump complete
--



CREATE TABLE IF NOT EXISTS "ABDC_DB".user_logins_detailed (
  user_id BIGSERIAL PRIMARY KEY,
  login_id VARCHAR(100) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  user_type VARCHAR(20) NOT NULL
    CHECK (user_type IN ('SUPER_ADMIN', 'ADMIN', 'SUB_ADMIN', 'USER')),
  employee_id BIGINT,
  student_id BIGINT,
  display_name VARCHAR(150),
  photo_path TEXT,
  account_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (account_status IN ('ACTIVE', 'INACTIVE', 'LOCKED')),
  force_password_change BOOLEAN NOT NULL DEFAULT TRUE,
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  last_login_at TIMESTAMP,
  created_by BIGINT
    REFERENCES "ABDC_DB".user_logins_detailed(user_id),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP,
  CONSTRAINT chk_login_person
    CHECK (NOT (employee_id IS NOT NULL AND student_id IS NOT NULL))
);
SET search_path = public;

CREATE TABLE public.section_groups (section_group_id BIGSERIAL PRIMARY KEY, programme_section_id BIGINT REFERENCES public.sections(section_id), group_name VARCHAR(100) NOT NULL, is_active BOOLEAN NOT NULL DEFAULT TRUE, UNIQUE(programme_section_id,group_name));

-- Additional legacy table structures; batch and section foreign keys use current master tables.
CREATE TABLE IF NOT EXISTS academics.attendance_sessions (
 attendance_session_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES public.sections(section_id),
 section_group_id BIGINT REFERENCES section_groups(section_group_id) ON DELETE SET NULL,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id),
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 academic_period_id BIGINT REFERENCES academics.academic_periods(period_id),
 attendance_date DATE NOT NULL,
 class_mode VARCHAR(20) NOT NULL DEFAULT 'Offline' CHECK(class_mode IN('Offline','Online')),
 topic_covered TEXT,
 session_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(session_status IN('Draft','Submitted','Locked','Cancelled')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 UNIQUE(programme_section_id,section_group_id,subject_id,attendance_date,academic_period_id)
);

CREATE TABLE IF NOT EXISTS academics.student_attendance (
 student_attendance_id BIGSERIAL PRIMARY KEY,
 attendance_session_id BIGINT NOT NULL REFERENCES academics.attendance_sessions(attendance_session_id) ON DELETE CASCADE,
 student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
 attendance_status VARCHAR(15) NOT NULL DEFAULT 'Present' CHECK(attendance_status IN('Present','Absent','Late','Leave','On Duty')),
 remarks TEXT,
 marked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 marked_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 UNIQUE(attendance_session_id,student_id)
);

CREATE TABLE IF NOT EXISTS academics.attendance_corrections (
 attendance_correction_id BIGSERIAL PRIMARY KEY,
 student_attendance_id BIGINT NOT NULL REFERENCES academics.student_attendance(student_attendance_id) ON DELETE CASCADE,
 old_status VARCHAR(15) NOT NULL,
 new_status VARCHAR(15) NOT NULL,
 correction_reason TEXT NOT NULL,
 correction_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(correction_status IN('Pending','Approved','Rejected')),
 requested_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 approved_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 decided_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS academics.examination_types (
 examination_type_id BIGSERIAL PRIMARY KEY,
 examination_type_code VARCHAR(30) NOT NULL UNIQUE,
 examination_type_name VARCHAR(100) NOT NULL UNIQUE,
 exam_scope VARCHAR(20) NOT NULL DEFAULT 'Internal' CHECK(exam_scope IN('Internal','External','University','Practical')),
 is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS academics.examinations (
 examination_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 examination_type_id BIGINT NOT NULL REFERENCES academics.examination_types(examination_type_id),
 examination_name VARCHAR(150) NOT NULL,
 start_date DATE,
 end_date DATE,
 result_status VARCHAR(20) NOT NULL DEFAULT 'Not Published' CHECK(result_status IN('Not Published','Published','Withheld')),
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 CHECK(end_date IS NULL OR start_date IS NULL OR end_date>=start_date)
);

CREATE TABLE IF NOT EXISTS academics.examination_subjects (
 examination_subject_id BIGSERIAL PRIMARY KEY,
 examination_id BIGINT NOT NULL REFERENCES academics.examinations(examination_id) ON DELETE CASCADE,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id),
 exam_date DATE,
 maximum_marks NUMERIC(7,2) NOT NULL CHECK(maximum_marks>0),
 pass_marks NUMERIC(7,2) NOT NULL CHECK(pass_marks>=0 AND pass_marks<=maximum_marks),
 marks_entry_deadline TIMESTAMPTZ,
 marks_lock_status VARCHAR(20) NOT NULL DEFAULT 'Open' CHECK(marks_lock_status IN('Open','Closed','Locked')),
 UNIQUE(examination_id,subject_id)
);

CREATE TABLE IF NOT EXISTS academics.student_marks (
 student_mark_id BIGSERIAL PRIMARY KEY,
 examination_subject_id BIGINT NOT NULL REFERENCES academics.examination_subjects(examination_subject_id) ON DELETE CASCADE,
 student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
 marks_obtained NUMERIC(7,2),
 attendance_status VARCHAR(15) NOT NULL DEFAULT 'Present' CHECK(attendance_status IN('Present','Absent','Malpractice','Withheld')),
 result_status VARCHAR(15) CHECK(result_status IN('Pass','Fail','Absent','Withheld')),
 remarks TEXT,
 entered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 entered_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 UNIQUE(examination_subject_id,student_id)
);

CREATE TABLE IF NOT EXISTS academics.university_marks_imports (
 university_marks_import_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 source_file_name VARCHAR(255),
 import_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(import_status IN('Pending','Processing','Completed','Failed')),
 total_rows INT NOT NULL DEFAULT 0,
 successful_rows INT NOT NULL DEFAULT 0,
 failed_rows INT NOT NULL DEFAULT 0,
 error_log TEXT,
 imported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 imported_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS academics.student_backpapers (
 student_backpaper_id BIGSERIAL PRIMARY KEY,
 student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 attempt_number INT NOT NULL DEFAULT 1 CHECK(attempt_number>0),
 registration_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(registration_status IN('Pending','Registered','Appeared','Cleared','Failed','Cancelled')),
 examination_id BIGINT REFERENCES academics.examinations(examination_id) ON DELETE SET NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(student_id,subject_id,attempt_number)
);

CREATE TABLE IF NOT EXISTS academics.lesson_plans (
 lesson_plan_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES public.sections(section_id),
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id),
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 plan_title VARCHAR(200) NOT NULL,
 planned_start_date DATE,
 planned_end_date DATE,
 total_planned_periods INT NOT NULL DEFAULT 0 CHECK(total_planned_periods>=0),
 plan_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(plan_status IN('Draft','Submitted','Approved','Rejected','Completed')),
 approved_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 approved_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 CHECK(planned_end_date IS NULL OR planned_start_date IS NULL OR planned_end_date>=planned_start_date)
);

CREATE TABLE IF NOT EXISTS academics.lesson_plan_units (
 lesson_plan_unit_id BIGSERIAL PRIMARY KEY,
 lesson_plan_id BIGINT NOT NULL REFERENCES academics.lesson_plans(lesson_plan_id) ON DELETE CASCADE,
 unit_number INT NOT NULL CHECK(unit_number>0),
 unit_title VARCHAR(200) NOT NULL,
 topics TEXT NOT NULL,
 planned_periods INT NOT NULL DEFAULT 0,
 completed_periods INT NOT NULL DEFAULT 0,
 planned_date DATE,
 completion_date DATE,
 completion_status VARCHAR(20) NOT NULL DEFAULT 'Not Started' CHECK(completion_status IN('Not Started','In Progress','Completed','Deferred')),
 UNIQUE(lesson_plan_id,unit_number)
);

CREATE TABLE IF NOT EXISTS academics.lesson_plan_co_mapping (
 lesson_plan_unit_id BIGINT NOT NULL REFERENCES academics.lesson_plan_units(lesson_plan_unit_id) ON DELETE CASCADE,
 course_outcome_id BIGINT NOT NULL REFERENCES academics.course_outcomes(course_outcome_id) ON DELETE CASCADE,
 PRIMARY KEY(lesson_plan_unit_id,course_outcome_id)
);

CREATE TABLE IF NOT EXISTS academics.preferred_books (
 preferred_book_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id) ON DELETE CASCADE,
 book_title VARCHAR(255) NOT NULL,
 author_name VARCHAR(200),
 publisher_name VARCHAR(200),
 edition VARCHAR(50),
 isbn VARCHAR(30),
 preference_type VARCHAR(20) NOT NULL DEFAULT 'Text Book' CHECK(preference_type IN('Text Book','Reference Book','Supplementary')),
 display_order INT NOT NULL DEFAULT 1,
 is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS academics.video_lectures (
 video_lecture_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id) ON DELETE CASCADE,
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 title VARCHAR(255) NOT NULL,
 unit_number INT,
 video_url TEXT NOT NULL,
 duration_minutes INT CHECK(duration_minutes IS NULL OR duration_minutes>=0),
 description TEXT,
 publish_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(publish_status IN('Draft','Published','Archived')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS academics.ppt_presentations (
 ppt_presentation_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id) ON DELETE CASCADE,
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 title VARCHAR(255) NOT NULL,
 unit_number INT,
 file_name VARCHAR(255),
 file_path TEXT,
 presentation_status VARCHAR(20) NOT NULL DEFAULT 'Submitted' CHECK(presentation_status IN('Draft','Submitted','Under Review','Approved','Revision Required','Rejected')),
 submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS academics.ppt_reviewers (
 ppt_reviewer_id BIGSERIAL PRIMARY KEY,
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE CASCADE,
 department_id BIGINT REFERENCES departments(department_id) ON DELETE SET NULL,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 UNIQUE(employee_id,department_id)
);

CREATE TABLE IF NOT EXISTS academics.ppt_reviews (
 ppt_review_id BIGSERIAL PRIMARY KEY,
 ppt_presentation_id BIGINT NOT NULL REFERENCES academics.ppt_presentations(ppt_presentation_id) ON DELETE CASCADE,
 reviewer_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 review_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(review_status IN('Pending','Approved','Revision Required','Rejected')),
 score NUMERIC(5,2) CHECK(score IS NULL OR score BETWEEN 0 AND 100),
 comments TEXT,
 reviewed_at TIMESTAMPTZ,
 UNIQUE(ppt_presentation_id,reviewer_employee_id)
);

CREATE TABLE IF NOT EXISTS academics.subject_teacher_allocations (
 subject_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES public.sections(section_id),
 section_group_id BIGINT REFERENCES section_groups(section_group_id) ON DELETE SET NULL,
 subject_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id),
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 allocation_role VARCHAR(20) NOT NULL DEFAULT 'Primary' CHECK(allocation_role IN('Primary','Co-Teacher','Practical','Tutorial')),
 workload_hours NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK(workload_hours>=0),
 effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
 effective_to DATE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 CHECK(effective_to IS NULL OR effective_to>=effective_from)
);

CREATE TABLE IF NOT EXISTS academics.class_teacher_allocations (
 class_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_section_id BIGINT NOT NULL REFERENCES public.sections(section_id),
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
 effective_to DATE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(effective_to IS NULL OR effective_to>=effective_from)
);

CREATE TABLE IF NOT EXISTS academics.substitute_teacher_allocations (
 substitute_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 subject_teacher_allocation_id BIGINT NOT NULL REFERENCES academics.subject_teacher_allocations(subject_teacher_allocation_id),
 original_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 substitute_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 substitution_date DATE NOT NULL,
 academic_period_id BIGINT REFERENCES academics.academic_periods(period_id),
 reason TEXT,
 status VARCHAR(20) NOT NULL DEFAULT 'Assigned' CHECK(status IN('Assigned','Completed','Cancelled','Restored')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(original_employee_id<>substitute_employee_id)
);

CREATE TABLE IF NOT EXISTS academics.teacher_allocation_history (
 teacher_allocation_history_id BIGSERIAL PRIMARY KEY,
 allocation_type VARCHAR(30) NOT NULL CHECK(allocation_type IN('Subject Teacher','Class Teacher','Substitute Teacher')),
 allocation_record_id BIGINT NOT NULL,
 action_type VARCHAR(20) NOT NULL CHECK(action_type IN('Created','Updated','Deactivated','Restored')),
 old_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE SET NULL,
 new_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE SET NULL,
 reason TEXT,
 action_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 action_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS academics.timetable_change_log (
 timetable_change_log_id BIGSERIAL PRIMARY KEY,
 timetable_entry_id BIGINT NOT NULL REFERENCES academics.timetable_entries(timetable_entry_id) ON DELETE CASCADE,
 change_type VARCHAR(20) NOT NULL CHECK(change_type IN('Created','Updated','Deleted','Substituted')),
 old_values JSONB,
 new_values JSONB,
 changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 changed_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS academics.report_runs (
 report_run_id BIGSERIAL PRIMARY KEY,
 report_code VARCHAR(80) NOT NULL,
 report_name VARCHAR(150) NOT NULL,
 filter_json JSONB,
 generated_format VARCHAR(10) NOT NULL DEFAULT 'PDF' CHECK(generated_format IN('PDF','XLSX','CSV','HTML')),
 file_path TEXT,
 row_count INT NOT NULL DEFAULT 0,
 generated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 generated_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);



/* ABDC_SOURCE_BEGIN server/ABDC_ERP_Complete_Database.sql SHA256 eecdd969ab2afc10c564b05875b2f1b880722a9f4d3b1e416b78d87da4d4f161
-- ABDC ERP consolidated PostgreSQL schema
-- Combines 7 supplied SQL files, with dependency ordering.
-- Target: PostgreSQL. Run against the desired database (e.g. psql -v ON_ERROR_STOP=1 -d your_db -f this_file).
-- IMPORTANT: Review compatibility notes below before applying to an existing database.
-- 1. Two supplied files define incompatible "ABDC_DB".user_logins structures.
--    The AMS bootstrap definition remains "ABDC_DB".user_logins; the other is
--    preserved as "ABDC_DB".user_logins_detailed (no data migration is performed).
-- 2. public.subject_masters was referenced but not defined by any supplied file;
--    the complete Add Subject definition and legacy column additions are included below.
-- 3. Existing legacy academics tables may be incompatible; the timetable script
--    deliberately raises an exception when it detects certain legacy layouts.
-- 4. CREATE TABLE IF NOT EXISTS does not reconcile existing table structures.
--    Test on a fresh database or staging copy first; back up before production use.
-- 5. No CREATE DATABASE statement: connect to the target database first.

BEGIN;


-- SECTION 1: AMS bootstrap / core tables
-- AMS ABDC PostgreSQL bootstrap schema
-- Run this file once against the database configured by DB_NAME in .env.
-- The backend safely creates the remaining feature-specific tables on startup.

CREATE SCHEMA IF NOT EXISTS public;
CREATE SCHEMA IF NOT EXISTS academics;
CREATE SCHEMA IF NOT EXISTS permission_management;
CREATE SCHEMA IF NOT EXISTS communication;
CREATE SCHEMA IF NOT EXISTS mentoring;
CREATE SCHEMA IF NOT EXISTS "ABDC_DB";

CREATE TABLE IF NOT EXISTS public.institutions (
  institution_id BIGSERIAL PRIMARY KEY,
  institution_code VARCHAR(30) NOT NULL UNIQUE,
  institution_name VARCHAR(200) NOT NULL,
  address_line1 TEXT,
  address_line2 TEXT,
  city VARCHAR(100), district VARCHAR(100), state VARCHAR(100),
  postal_code VARCHAR(20), phone VARCHAR(20), email VARCHAR(150), website TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.campuses (
  campus_id BIGSERIAL PRIMARY KEY,
  institution_id BIGINT NOT NULL REFERENCES public.institutions(institution_id) ON DELETE CASCADE,
  campus_code VARCHAR(30) NOT NULL,
  campus_name VARCHAR(150) NOT NULL,
  address TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (institution_id, campus_code)
);

CREATE TABLE IF NOT EXISTS public.designations (
  designation_id BIGSERIAL PRIMARY KEY,
  designation_code VARCHAR(30) UNIQUE,
  designation_name VARCHAR(150) NOT NULL UNIQUE,
  short_name VARCHAR(50),
  category VARCHAR(50),
  designation_type VARCHAR(30) NOT NULL DEFAULT 'TEACHING',
  designation_level INTEGER,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.departments (
  department_id BIGSERIAL PRIMARY KEY,
  institution_id BIGINT NOT NULL REFERENCES public.institutions(institution_id) ON DELETE CASCADE,
  department_code VARCHAR(30) NOT NULL,
  department_name VARCHAR(150) NOT NULL,
  department_alias VARCHAR(150),
  department_type VARCHAR(50),
  hod_employee_id BIGINT,
  official_email VARCHAR(150),
  phone VARCHAR(20),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (institution_id, department_code)
);

CREATE TABLE IF NOT EXISTS public.buildings (
  building_id BIGSERIAL PRIMARY KEY,
  campus_id BIGINT NOT NULL REFERENCES public.campuses(campus_id) ON DELETE CASCADE,
  building_code VARCHAR(30) NOT NULL,
  building_name VARCHAR(150) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (campus_id, building_code)
);

CREATE TABLE IF NOT EXISTS public.users (
  user_id BIGSERIAL PRIMARY KEY,
  username VARCHAR(80) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  email VARCHAR(150) UNIQUE,
  mobile VARCHAR(20),
  display_name VARCHAR(150),
  full_name VARCHAR(150),
  user_type VARCHAR(30) NOT NULL,
  user_type_id BIGINT,
  employee_id BIGINT,
  student_id BIGINT,
  photo_path TEXT,
  user_status VARCHAR(20) DEFAULT 'Active',
  remarks TEXT,
  must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
  password_changed_at TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  failed_login_count INTEGER NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.employees (
  employee_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT UNIQUE REFERENCES public.users(user_id) ON DELETE SET NULL,
  institution_id BIGINT NOT NULL REFERENCES public.institutions(institution_id),
  department_id BIGINT REFERENCES public.departments(department_id),
  designation_id BIGINT REFERENCES public.designations(designation_id),
  campus_id BIGINT REFERENCES public.campuses(campus_id),
  reporting_employee_id BIGINT REFERENCES public.employees(employee_id) ON DELETE SET NULL,
  employee_code VARCHAR(30) NOT NULL UNIQUE,
  first_name VARCHAR(100) NOT NULL,
  middle_name VARCHAR(100), last_name VARCHAR(100), gender VARCHAR(20),
  date_of_birth DATE, date_of_joining DATE, employment_type VARCHAR(40),
  employee_category VARCHAR(40), official_email VARCHAR(150) UNIQUE,
  personal_email VARCHAR(150), mobile VARCHAR(20), alternate_mobile VARCHAR(20),
  address TEXT, permanent_address TEXT, blood_group VARCHAR(10),
  marital_status VARCHAR(20), aadhaar_number VARCHAR(20), pan_number VARCHAR(20),
  photo_url TEXT, bank_name VARCHAR(150), bank_account_number VARCHAR(50),
  bank_ifsc VARCHAR(20), bank_branch VARCHAR(150),
  document_names JSONB NOT NULL DEFAULT '[]'::JSONB,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.departments DROP CONSTRAINT IF EXISTS departments_hod_employee_fk;
ALTER TABLE public.departments ADD CONSTRAINT departments_hod_employee_fk
  FOREIGN KEY (hod_employee_id) REFERENCES public.employees(employee_id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.academic_years (
  academic_year_id BIGSERIAL PRIMARY KEY,
  institution_id BIGINT NOT NULL REFERENCES public.institutions(institution_id),
  year_label VARCHAR(30) NOT NULL,
  academic_year_name VARCHAR(120),
  start_date DATE NOT NULL, end_date DATE NOT NULL,
  admission_start_date DATE, admission_end_date DATE,
  is_current BOOLEAN NOT NULL DEFAULT FALSE,
  allow_data_entry BOOLEAN NOT NULL DEFAULT TRUE,
  allow_previous_year_edit BOOLEAN NOT NULL DEFAULT FALSE,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (institution_id, year_label)
);

CREATE TABLE IF NOT EXISTS public.programmes (
  programme_id BIGSERIAL PRIMARY KEY,
  institution_id BIGINT NOT NULL REFERENCES public.institutions(institution_id),
  department_id BIGINT REFERENCES public.departments(department_id),
  programme_code VARCHAR(30) NOT NULL,
  programme_name VARCHAR(150) NOT NULL,
  programme_short_name VARCHAR(50),
  programme_level VARCHAR(50), programme_type VARCHAR(50),
  duration_years NUMERIC(4,1), duration_semesters INTEGER,
  intake_capacity INTEGER, status VARCHAR(20) DEFAULT 'ACTIVE',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (institution_id, programme_code)
);

CREATE TABLE IF NOT EXISTS public.admission_batches (
  batch_id BIGSERIAL PRIMARY KEY,
  programme_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  academic_year_id BIGINT REFERENCES public.academic_years(academic_year_id),
  batch_code VARCHAR(40), batch_name VARCHAR(100),
  start_year INTEGER, end_year INTEGER, intake_capacity INTEGER,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (programme_id, batch_code)
);

CREATE TABLE IF NOT EXISTS public.semesters (
  semester_id BIGSERIAL PRIMARY KEY,
  programme_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  semester_number INTEGER NOT NULL,
  semester_name VARCHAR(100),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (programme_id, semester_number)
);

CREATE TABLE IF NOT EXISTS public.academic_terms (
  term_id BIGSERIAL PRIMARY KEY,
  academic_year_id BIGINT NOT NULL REFERENCES public.academic_years(academic_year_id),
  term_name VARCHAR(100) NOT NULL, term_type VARCHAR(30),
  start_date DATE, end_date DATE, status VARCHAR(20) DEFAULT 'ACTIVE'
);

CREATE TABLE IF NOT EXISTS public.section_masters (
  section_master_id BIGSERIAL PRIMARY KEY,
  section_master_code VARCHAR(30) UNIQUE,
  section_master_name VARCHAR(100) NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.sections (
  section_id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
  semester_id BIGINT NOT NULL REFERENCES public.semesters(semester_id),
  term_id BIGINT REFERENCES public.academic_terms(term_id),
  section_master_id BIGINT REFERENCES public.section_masters(section_master_id),
  section_name VARCHAR(100) NOT NULL,
  strength_limit INTEGER DEFAULT 60,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.students (
  student_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT UNIQUE REFERENCES public.users(user_id) ON DELETE SET NULL,
  institution_id BIGINT NOT NULL REFERENCES public.institutions(institution_id),
  academic_year_id BIGINT REFERENCES public.academic_years(academic_year_id),
  programme_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  batch_id BIGINT REFERENCES public.admission_batches(batch_id),
  semester_id BIGINT REFERENCES public.semesters(semester_id),
  section_id BIGINT REFERENCES public.sections(section_id),
  student_code VARCHAR(40) UNIQUE,
  registration_number VARCHAR(50) UNIQUE,
  registration_no VARCHAR(50), roll_number VARCHAR(50),
  first_name VARCHAR(100) NOT NULL, middle_name VARCHAR(100), last_name VARCHAR(100),
  gender VARCHAR(20), date_of_birth DATE,
  email VARCHAR(150), mobile VARCHAR(20), mobile_number VARCHAR(20),
  profile_photo_url TEXT, photo_url TEXT, student_group VARCHAR(30),
  status VARCHAR(20) DEFAULT 'ACTIVE', is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.student_parents (
  student_parent_id BIGSERIAL PRIMARY KEY,
  student_id BIGINT NOT NULL REFERENCES public.students(student_id) ON DELETE CASCADE,
  father_name VARCHAR(150), mother_name VARCHAR(150), guardian_name VARCHAR(150),
  guardian_mobile VARCHAR(20), guardian_email VARCHAR(150)
);

CREATE TABLE IF NOT EXISTS public.student_addresses (
  student_address_id BIGSERIAL PRIMARY KEY,
  student_id BIGINT NOT NULL REFERENCES public.students(student_id) ON DELETE CASCADE,
  address_type VARCHAR(30) NOT NULL, address TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "ABDC_DB".user_logins (
  user_login_id BIGSERIAL PRIMARY KEY,
  username VARCHAR(100) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  full_name VARCHAR(150), email VARCHAR(150), role VARCHAR(50) NOT NULL DEFAULT 'USER',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS employees_institution_id_idx ON public.employees(institution_id);
CREATE INDEX IF NOT EXISTS employees_department_id_idx ON public.employees(department_id);
CREATE INDEX IF NOT EXISTS employees_status_idx ON public.employees(status);
CREATE INDEX IF NOT EXISTS students_programme_id_idx ON public.students(programme_id);
CREATE INDEX IF NOT EXISTS students_section_id_idx ON public.students(section_id);

-- SECTION 2: employee indexes and metadata
CREATE INDEX IF NOT EXISTS employees_designation_id_idx ON public.employees(designation_id);
COMMENT ON TABLE public.employees IS 'Employee master records used by the AMS application.';

-- SECTION 3: alternate detailed login structure
CREATE SCHEMA IF NOT EXISTS "ABDC_DB";

CREATE TABLE IF NOT EXISTS "ABDC_DB".user_logins_detailed (
  user_id BIGSERIAL PRIMARY KEY,
  login_id VARCHAR(100) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  user_type VARCHAR(20) NOT NULL
    CHECK (user_type IN ('SUPER_ADMIN', 'ADMIN', 'SUB_ADMIN', 'USER')),
  employee_id BIGINT,
  student_id BIGINT,
  display_name VARCHAR(150),
  photo_path TEXT,
  account_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (account_status IN ('ACTIVE', 'INACTIVE', 'LOCKED')),
  force_password_change BOOLEAN NOT NULL DEFAULT TRUE,
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  last_login_at TIMESTAMP,
  created_by BIGINT
    REFERENCES "ABDC_DB".user_logins_detailed(user_id),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP,
  CONSTRAINT chk_login_person
    CHECK (NOT (employee_id IS NOT NULL AND student_id IS NOT NULL))
);

-- SECTION 4: programme-semester definitions
CREATE TABLE IF NOT EXISTS public.programme_semester_definitions (
  programme_semester_id BIGSERIAL PRIMARY KEY,
  course_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
  semester_id BIGINT NOT NULL REFERENCES public.semesters(semester_id),
  class_type VARCHAR(20) NOT NULL CHECK (class_type IN ('SECTION', 'HOUSE')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  consider_for_accounting BOOLEAN NOT NULL DEFAULT FALSE,
  created_by BIGINT REFERENCES public.users(user_id),
  updated_by BIGINT REFERENCES public.users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ,
  CONSTRAINT uq_programme_semester_definition
    UNIQUE (course_id, programme_batch_id, semester_id, class_type)
);

CREATE INDEX IF NOT EXISTS idx_programme_semester_course
  ON programme_semester_definitions(course_id);

CREATE INDEX IF NOT EXISTS idx_programme_semester_batch
  ON programme_semester_definitions(programme_batch_id);

CREATE INDEX IF NOT EXISTS idx_programme_semester_semester
  ON programme_semester_definitions(semester_id);


-- SECTION 5: classroom module
-- PostgreSQL classroom module for server/index.js.
-- Prerequisites: public.campuses, public.buildings, public.users.

CREATE TABLE IF NOT EXISTS public.classroom_types (
 classroom_type_id BIGSERIAL PRIMARY KEY,
 classroom_type_code VARCHAR(40) NOT NULL UNIQUE,
 classroom_type_name VARCHAR(100) NOT NULL UNIQUE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS public.classroom_facility_masters (
 facility_id BIGSERIAL PRIMARY KEY,
 facility_code VARCHAR(40) NOT NULL UNIQUE,
 facility_name VARCHAR(100) NOT NULL UNIQUE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS public.classrooms (
 classroom_id BIGSERIAL PRIMARY KEY,
 campus_id BIGINT NOT NULL REFERENCES public.campuses(campus_id),
 building_id BIGINT NOT NULL REFERENCES public.buildings(building_id),
 classroom_type_id BIGINT NOT NULL REFERENCES public.classroom_types(classroom_type_id),
 room_no VARCHAR(50) NOT NULL, room_name VARCHAR(150), floor_name VARCHAR(50),
 student_capacity INTEGER NOT NULL CHECK(student_capacity >= 0), description TEXT,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_by BIGINT REFERENCES public.users(user_id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_by BIGINT REFERENCES public.users(user_id), updated_at TIMESTAMPTZ,
 UNIQUE(building_id,room_no)
);
CREATE TABLE IF NOT EXISTS public.classroom_facilities (
 classroom_id BIGINT NOT NULL REFERENCES public.classrooms(classroom_id) ON DELETE CASCADE,
 facility_id BIGINT NOT NULL REFERENCES public.classroom_facility_masters(facility_id),
 PRIMARY KEY(classroom_id,facility_id)
);
CREATE TABLE IF NOT EXISTS public.classroom_unavailability (
 classroom_unavailability_id BIGSERIAL PRIMARY KEY,
 classroom_id BIGINT NOT NULL REFERENCES public.classrooms(classroom_id) ON DELETE CASCADE,
 start_at TIMESTAMPTZ NOT NULL, end_at TIMESTAMPTZ NOT NULL,
 reason TEXT, created_by BIGINT REFERENCES public.users(user_id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CHECK(end_at > start_at)
);
INSERT INTO public.classroom_types(classroom_type_code,classroom_type_name) VALUES
 ('CLASSROOM','Classroom'),('LABORATORY','Laboratory'),('SEMINAR_HALL','Seminar Hall')
 ON CONFLICT DO NOTHING;
INSERT INTO public.classroom_facility_masters(facility_code,facility_name) VALUES
 ('PROJECTOR','Projector'),('WHITEBOARD','Whiteboard'),('COMPUTERS','Computers'),('AC','Air Conditioning')
 ON CONFLICT DO NOTHING;

-- SECTION 6: login history
-- PostgreSQL login history for the current AMS backend.
-- Prerequisite: public.users(user_id). Uses the database selected in .env.
-- Re-running preserves existing records; this is not a legacy-schema migration.

CREATE TABLE IF NOT EXISTS public.login_history (
    login_history_id BIGSERIAL PRIMARY KEY,
    -- Unknown usernames can generate failed attempts without a user record.
    user_id BIGINT REFERENCES public.users(user_id) ON DELETE SET NULL,
    username TEXT NOT NULL,
    login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    logout_at TIMESTAMPTZ,
    ip_address INET,
    user_agent TEXT,
    browser_name VARCHAR(100),
    operating_system VARCHAR(100),
    device_type VARCHAR(50),
    -- SHA-256 digest only; never store the raw session token here.
    session_token_hash VARCHAR(64),
    login_status VARCHAR(30) NOT NULL,
    login_success BOOLEAN NOT NULL,
    failure_reason TEXT,
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    logout_type VARCHAR(30)
);

CREATE INDEX IF NOT EXISTS login_history_login_at_idx
    ON public.login_history (login_at DESC);
CREATE INDEX IF NOT EXISTS login_history_user_id_idx
    ON public.login_history (user_id);

-- SECTION 7: programme/semester subject masters and separate components
-- Academic subject master used by Subjects > Add Subject.
CREATE TABLE IF NOT EXISTS public.subject_masters (
  subject_master_id BIGSERIAL PRIMARY KEY,
  subject_code VARCHAR(30) NOT NULL,
  subject_name VARCHAR(200) NOT NULL,
  subject_short_name VARCHAR(50),
  subject_type VARCHAR(30) NOT NULL DEFAULT 'Theory',
  subject_category VARCHAR(80) NOT NULL,
  department_id BIGINT NOT NULL REFERENCES public.departments(department_id),
  credit NUMERIC(5,2) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by BIGINT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by BIGINT,
  updated_at TIMESTAMP
);
-- Extend older minimal tables without changing existing subjects.
ALTER TABLE public.subject_masters
  ADD COLUMN IF NOT EXISTS subject_short_name VARCHAR(50),
  ADD COLUMN IF NOT EXISTS subject_type VARCHAR(30) NOT NULL DEFAULT 'Theory',
  ADD COLUMN IF NOT EXISTS subject_category VARCHAR(80) NOT NULL DEFAULT 'Professional Core',
  ADD COLUMN IF NOT EXISTS department_id BIGINT REFERENCES public.departments(department_id),
  ADD COLUMN IF NOT EXISTS credit NUMERIC(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_by BIGINT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by BIGINT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;
-- Legacy rows may have no department; assign their correct department before use.
CREATE INDEX IF NOT EXISTS subject_masters_department_idx ON public.subject_masters(department_id);

-- Programme/semester subjects retain their existing primary keys and downstream references.
ALTER TABLE public.subject_masters
  ADD COLUMN IF NOT EXISTS programme_id BIGINT REFERENCES public.programmes(programme_id),
  ADD COLUMN IF NOT EXISTS semester_id BIGINT REFERENCES public.semesters(semester_id);
ALTER TABLE public.subject_masters ALTER COLUMN department_id DROP NOT NULL;
-- Replace only the old single-column code constraint; existing subject data is preserved.
DO $subjects$ DECLARE item RECORD; BEGIN
  FOR item IN SELECT conname FROM pg_constraint WHERE conrelid='public.subject_masters'::regclass
    AND contype='u' AND conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='public.subject_masters'::regclass AND attname='subject_code')]::smallint[]
  LOOP EXECUTE format('ALTER TABLE public.subject_masters DROP CONSTRAINT %I',item.conname); END LOOP;
END $subjects$;
CREATE UNIQUE INDEX IF NOT EXISTS subject_masters_legacy_code_uq ON public.subject_masters(subject_code)
  WHERE programme_id IS NULL AND semester_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS subject_masters_programme_semester_code_uq ON public.subject_masters(programme_id,semester_id,UPPER(subject_code))
  WHERE programme_id IS NOT NULL AND semester_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS semesters_id_programme_uq ON public.semesters(semester_id,programme_id);
DO $subjects$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.subject_masters'::regclass AND conname='subject_masters_scope_check') THEN
    ALTER TABLE public.subject_masters ADD CONSTRAINT subject_masters_scope_check CHECK ((programme_id IS NULL)=(semester_id IS NULL)) NOT VALID;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.subject_masters'::regclass AND conname='subject_masters_semester_programme_fk') THEN
    ALTER TABLE public.subject_masters ADD CONSTRAINT subject_masters_semester_programme_fk FOREIGN KEY(semester_id,programme_id) REFERENCES public.semesters(semester_id,programme_id) NOT VALID;
  END IF;
END $subjects$;
CREATE TABLE IF NOT EXISTS public.subject_components (
  subject_component_id BIGSERIAL PRIMARY KEY,
  subject_master_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id) ON DELETE CASCADE,
  subject_type VARCHAR(20) NOT NULL CHECK(subject_type IN ('THEORY','PRACTICAL')),
  credit NUMERIC(5,2) NOT NULL CHECK(credit>=0),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP,
  UNIQUE(subject_master_id,subject_type)
);
-- Legacy type/credit columns remain available for existing module queries.
-- Existing subjects are not assigned a guessed programme, semester or component.

-- One row per component: Theory and Practical share the subject code and name.
-- Adding a missing component reuses the same subject_master_id.
-- An existing THEORY row and a new PRACTICAL row share one master; credits stay separate.
-- Component uniqueness is (subject_master_id, subject_type), never subject_code alone.
CREATE OR REPLACE VIEW public.subject_component_list AS
SELECT sm.subject_master_id,sc.subject_component_id,sm.programme_id,sm.semester_id,
  p.programme_code,s.semester_name,sm.subject_code,sm.subject_name,
  sc.subject_type,sc.credit,sm.is_active
FROM public.subject_masters sm
JOIN public.subject_components sc ON sc.subject_master_id=sm.subject_master_id
JOIN public.programmes p ON p.programme_id=sm.programme_id
JOIN public.semesters s ON s.semester_id=sm.semester_id;

-- SECTION 8: timetable module
-- PostgreSQL timetable module matching the current server/index.js.
-- Prerequisites: public.users, academic_years, programmes, admission_batches,
-- semesters, sections, subject_masters; import the classroom module first.
-- Does not migrate the incompatible legacy src/abit_ims_academics_module.sql tables.

CREATE SCHEMA IF NOT EXISTS academics;
DO $$
BEGIN
 IF to_regclass('academics.academic_periods') IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM information_schema.columns WHERE table_schema='academics'
   AND table_name='academic_periods' AND column_name='time_configuration_id'
 ) THEN
  RAISE EXCEPTION 'Legacy academics.academic_periods detected. Migrate the legacy academics schema before importing this module.';
 END IF;
 IF to_regclass('academics.timetable_headers') IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM information_schema.columns WHERE table_schema='academics'
   AND table_name='timetable_headers' AND column_name='time_configuration_id'
 ) THEN
  RAISE EXCEPTION 'Legacy academics.timetable_headers detected. Migrate the legacy academics schema before importing this module.';
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS academics.week_days (
 week_day_id BIGSERIAL PRIMARY KEY, day_number INTEGER NOT NULL UNIQUE CHECK(day_number BETWEEN 1 AND 7),
 day_name VARCHAR(20) NOT NULL UNIQUE, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO academics.week_days(day_number,day_name) VALUES
 (1,'Monday'),(2,'Tuesday'),(3,'Wednesday'),(4,'Thursday'),(5,'Friday'),(6,'Saturday'),(7,'Sunday')
 ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS academics.academic_time_configurations (
 time_configuration_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES public.academic_years(academic_year_id),
 configuration_name VARCHAR(150) NOT NULL,
 college_start_time TIME NOT NULL, college_end_time TIME NOT NULL,
 teaching_period_minutes INTEGER NOT NULL CHECK(teaching_period_minutes > 0),
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_by BIGINT REFERENCES public.users(user_id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_by BIGINT REFERENCES public.users(user_id), updated_at TIMESTAMPTZ,
 UNIQUE(academic_year_id,configuration_name), CHECK(college_end_time > college_start_time)
);
CREATE TABLE IF NOT EXISTS academics.academic_time_configuration_days (
 time_configuration_id BIGINT NOT NULL REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE CASCADE,
 week_day_id BIGINT NOT NULL REFERENCES academics.week_days(week_day_id),
 PRIMARY KEY(time_configuration_id,week_day_id)
);
CREATE TABLE IF NOT EXISTS academics.academic_breaks (
 academic_break_id BIGSERIAL PRIMARY KEY,
 time_configuration_id BIGINT NOT NULL REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE CASCADE,
 break_name VARCHAR(100) NOT NULL, break_type VARCHAR(40) NOT NULL,
 start_time TIME NOT NULL, end_time TIME NOT NULL, display_order INTEGER NOT NULL,
 created_by BIGINT REFERENCES public.users(user_id), CHECK(end_time > start_time)
);
CREATE TABLE IF NOT EXISTS academics.academic_periods (
 period_id BIGSERIAL PRIMARY KEY,
 time_configuration_id BIGINT NOT NULL REFERENCES academics.academic_time_configurations(time_configuration_id) ON DELETE CASCADE,
 period_code VARCHAR(40) NOT NULL, period_name VARCHAR(100) NOT NULL,
 start_time TIME NOT NULL, end_time TIME NOT NULL,
 duration_minutes INTEGER NOT NULL CHECK(duration_minutes > 0),
 period_type VARCHAR(40) NOT NULL, display_order INTEGER NOT NULL,
 is_teaching_period BOOLEAN NOT NULL DEFAULT TRUE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
 UNIQUE(time_configuration_id,period_code), CHECK(end_time > start_time)
);
CREATE TABLE IF NOT EXISTS academics.timetable_headers (
 timetable_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES public.academic_years(academic_year_id),
 programme_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
 programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES public.semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES public.sections(section_id),
 group_id BIGINT,
 time_configuration_id BIGINT NOT NULL REFERENCES academics.academic_time_configurations(time_configuration_id),
 timetable_name VARCHAR(200) NOT NULL, effective_from DATE NOT NULL, effective_to DATE,
 timetable_status VARCHAR(30) NOT NULL DEFAULT 'Draft', version_number INTEGER NOT NULL DEFAULT 1,
 remarks TEXT, created_by BIGINT REFERENCES public.users(user_id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_by BIGINT REFERENCES public.users(user_id), updated_at TIMESTAMPTZ,
 published_by BIGINT REFERENCES public.users(user_id), published_at TIMESTAMPTZ,
 CHECK(effective_to IS NULL OR effective_to >= effective_from),
 UNIQUE(academic_year_id,programme_batch_id,semester_id,programme_section_id,version_number)
);
CREATE TABLE IF NOT EXISTS academics.timetable_working_days (
 timetable_id BIGINT NOT NULL REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE,
 week_day_id BIGINT NOT NULL REFERENCES academics.week_days(week_day_id),
 is_working_day BOOLEAN NOT NULL DEFAULT TRUE, display_order INTEGER NOT NULL,
 PRIMARY KEY(timetable_id,week_day_id)
);
CREATE TABLE IF NOT EXISTS academics.timetable_entries (
 timetable_entry_id BIGSERIAL PRIMARY KEY,
 timetable_id BIGINT NOT NULL REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE,
 week_day_id BIGINT NOT NULL REFERENCES academics.week_days(week_day_id),
 period_id BIGINT NOT NULL REFERENCES academics.academic_periods(period_id),
 subject_id BIGINT REFERENCES public.subject_masters(subject_master_id),
 classroom_id BIGINT REFERENCES public.classrooms(classroom_id),
 entry_type VARCHAR(40) NOT NULL, display_text TEXT,
 created_by BIGINT REFERENCES public.users(user_id), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 UNIQUE(timetable_id,week_day_id,period_id)
);
CREATE TABLE IF NOT EXISTS academics.timetable_change_logs (
 timetable_change_log_id BIGSERIAL PRIMARY KEY,
 timetable_id BIGINT NOT NULL REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE,
 action_type VARCHAR(50) NOT NULL, old_value JSONB, new_value JSONB, change_reason TEXT,
 changed_by BIGINT REFERENCES public.users(user_id), changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- Course tab: initial batch and section links
-- Course fields are stored in the shared programmes, batches and sections tables.
ALTER TABLE public.programmes
  ADD COLUMN IF NOT EXISTS programme_alias VARCHAR(100),
  ADD COLUMN IF NOT EXISTS programme_type VARCHAR(40) NOT NULL DEFAULT 'UNDERGRADUATE',
  ADD COLUMN IF NOT EXISTS total_semesters INTEGER NOT NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS award_type VARCHAR(40) NOT NULL DEFAULT 'DEGREE',
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE public.admission_batches
  ADD COLUMN IF NOT EXISTS batch_alias VARCHAR(50),
  ADD COLUMN IF NOT EXISTS admission_year INTEGER,
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS expected_end_date DATE,
  ADD COLUMN IF NOT EXISTS approved_intake INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lateral_entry_intake INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE public.admission_batches ALTER COLUMN batch_name TYPE VARCHAR(100);
ALTER TABLE public.sections ALTER COLUMN section_name TYPE VARCHAR(100);
ALTER TABLE public.semesters ADD COLUMN IF NOT EXISTS year_number INTEGER;
ALTER TABLE public.sections ADD COLUMN IF NOT EXISTS strength_limit INTEGER;

-- programmes remains the shared course master used by subjects and allocations.
-- Store the initial batch and section created by the compact Course form.
CREATE TABLE IF NOT EXISTS public.course_initial_setup (
  course_id BIGINT PRIMARY KEY REFERENCES public.programmes(programme_id) ON DELETE CASCADE,
  batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE,
  section_id BIGINT NOT NULL REFERENCES public.sections(section_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS course_initial_setup_batch_idx ON public.course_initial_setup(batch_id);


-- Course > Batch: survey eligibility
-- Shared batch master used by Course > Batch and academic allocations.
CREATE TABLE IF NOT EXISTS public.admission_batches (
  batch_id BIGSERIAL PRIMARY KEY,
  programme_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  admission_year SMALLINT NOT NULL,
  batch_name VARCHAR(100) NOT NULL,
  batch_alias VARCHAR(50),
  start_date DATE,
  expected_end_date DATE,
  approved_intake INTEGER NOT NULL DEFAULT 0,
  lateral_entry_intake INTEGER NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(programme_id,admission_year)
);
CREATE TABLE IF NOT EXISTS public.batch_survey_settings (
  batch_id BIGINT PRIMARY KEY REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE,
  annual_survey_eligible BOOLEAN NOT NULL DEFAULT FALSE,
  exit_survey_eligible BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- Course > Assign Section
-- Batch-level section assignment displayed in Course > Assign Section.
-- Academic sections remain semester-specific for attendance and teacher allocation.
CREATE TABLE IF NOT EXISTS public.batch_section_assignments (
  assignment_id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE,
  section_master_id BIGINT NOT NULL REFERENCES public.section_masters(section_master_id),
  initial_section_id BIGINT REFERENCES public.sections(section_id) ON DELETE SET NULL,
  intake INTEGER NOT NULL CHECK(intake>0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE(batch_id,section_master_id)
);
-- Preserve existing assignments; represent each batch/master once in the table.
INSERT INTO public.batch_section_assignments(batch_id,section_master_id,initial_section_id,intake,is_active)
SELECT DISTINCT ON(s.batch_id,s.section_master_id) s.batch_id,s.section_master_id,s.section_id,GREATEST(COALESCE(s.strength_limit,1),1),s.is_active
FROM public.sections s JOIN public.semesters se ON se.semester_id=s.semester_id
WHERE s.section_master_id IS NOT NULL
ORDER BY s.batch_id,s.section_master_id,se.semester_number,s.section_id
ON CONFLICT(batch_id,section_master_id) DO NOTHING;


-- Course > Add Section: master and course mappings
-- Section definitions configured by Course > Add Section.
-- Kept separate from semester-specific academic sections and batch assignments.
CREATE TABLE IF NOT EXISTS public.section_definitions (
  section_definition_id BIGSERIAL PRIMARY KEY,
  section_name VARCHAR(100) NOT NULL,
  section_master_id BIGINT NOT NULL REFERENCES public.section_masters(section_master_id),
  admission_course_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  course_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  created_by BIGINT REFERENCES public.users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS section_definitions_mapping_uq
  ON public.section_definitions(LOWER(section_name),section_master_id,admission_course_id,course_id);
CREATE INDEX IF NOT EXISTS section_definitions_course_idx ON public.section_definitions(course_id);


-- Course > Section Master: audit fields and normalized name uniqueness
CREATE TABLE IF NOT EXISTS public.section_masters (
  section_master_id BIGSERIAL PRIMARY KEY,
  section_master_code VARCHAR(30) UNIQUE NOT NULL,
  section_master_name VARCHAR(100) UNIQUE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by BIGINT REFERENCES public.users(user_id),
  updated_at TIMESTAMPTZ,
  updated_by BIGINT REFERENCES public.users(user_id)
);
ALTER TABLE public.section_masters
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES public.users(user_id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_by BIGINT REFERENCES public.users(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS section_masters_name_normalized_uq ON public.section_masters(LOWER(TRIM(section_master_name)));


-- Employee profile fields saved directly in the employee table
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS profile_details JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Readable labels for batches created by student imports
-- Correct only the numeric programme-id batch labels generated by older student imports.
-- Preserve custom batch names and all student/batch relationships.
UPDATE public.admission_batches b
SET batch_name=b.admission_year::text||'-'||COALESCE(EXTRACT(YEAR FROM b.expected_end_date)::integer,b.admission_year+CEIL(p.duration_years)::integer)::text
FROM public.programmes p
WHERE p.programme_id=b.programme_id AND b.admission_year>0 AND p.duration_years>0
  AND b.batch_name=b.programme_id::text||'-'||b.admission_year::text;

CREATE SCHEMA IF NOT EXISTS mentoring;
-- Tables used by Reviewer Allotment, Counselling & Reviews, Mentor Activity and Mentor Assignment.
CREATE TABLE IF NOT EXISTS mentoring.communication_modes (
  "communication_mode_id" BIGSERIAL NOT NULL,
  "mode_code" character varying(30) NOT NULL,
  "mode_name" character varying(100) NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "communication_modes_mode_code_key" UNIQUE (mode_code),
  CONSTRAINT "communication_modes_mode_name_key" UNIQUE (mode_name),
  CONSTRAINT "communication_modes_pkey" PRIMARY KEY (communication_mode_id)
);
CREATE TABLE IF NOT EXISTS mentoring.counselling_purposes (
  "counselling_purpose_id" BIGSERIAL NOT NULL,
  "purpose_code" character varying(30) NOT NULL,
  "purpose_name" character varying(100) NOT NULL,
  "description" text,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "counselling_purposes_pkey" PRIMARY KEY (counselling_purpose_id),
  CONSTRAINT "counselling_purposes_purpose_code_key" UNIQUE (purpose_code),
  CONSTRAINT "counselling_purposes_purpose_name_key" UNIQUE (purpose_name)
);
CREATE TABLE IF NOT EXISTS mentoring.employee_mentor_eligibility (
  "employee_mentor_eligibility_id" BIGSERIAL NOT NULL,
  "employee_id" bigint NOT NULL,
  "is_mentor_for_new_students" boolean NOT NULL DEFAULT false,
  "maximum_students" integer NOT NULL DEFAULT 30,
  "effective_from" date NOT NULL DEFAULT CURRENT_DATE,
  "effective_to" date,
  "eligibility_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "remarks" text,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "employee_mentor_eligibility_employee_id_key" UNIQUE (employee_id),
  CONSTRAINT "employee_mentor_eligibility_pkey" PRIMARY KEY (employee_mentor_eligibility_id),
  CONSTRAINT "employee_mentor_eligibility_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from))),
  CONSTRAINT "employee_mentor_eligibility_eligibility_status_check" CHECK (((eligibility_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Suspended'::character varying)::text]))),
  CONSTRAINT "employee_mentor_eligibility_maximum_students_check" CHECK ((maximum_students > 0))
);
CREATE TABLE IF NOT EXISTS mentoring.employee_mentor_eligibility_history (
  "employee_mentor_eligibility_history_id" BIGSERIAL NOT NULL,
  "employee_mentor_eligibility_id" bigint NOT NULL,
  "old_is_mentor" boolean,
  "new_is_mentor" boolean NOT NULL,
  "old_maximum_students" integer,
  "new_maximum_students" integer,
  "change_reason" text,
  "changed_by" bigint,
  "changed_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "employee_mentor_eligibility_history_pkey" PRIMARY KEY (employee_mentor_eligibility_history_id)
);
CREATE TABLE IF NOT EXISTS mentoring.mentors (
  "mentor_id" BIGSERIAL NOT NULL,
  "employee_id" bigint NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "department_id" bigint,
  "maximum_students" integer NOT NULL DEFAULT 30,
  "mentor_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "created_by" bigint,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  "employee_mentor_eligibility_id" bigint,
  "effective_from" date NOT NULL DEFAULT CURRENT_DATE,
  "effective_to" date,
  CONSTRAINT "mentors_employee_id_key" UNIQUE (employee_id),
  CONSTRAINT "mentors_pkey" PRIMARY KEY (mentor_id),
  CONSTRAINT "mentors_effective_dates_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);
CREATE TABLE IF NOT EXISTS mentoring.reviewers (
  "reviewer_id" BIGSERIAL NOT NULL,
  "employee_id" bigint NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "reviewers_employee_id_key" UNIQUE (employee_id),
  CONSTRAINT "reviewers_pkey" PRIMARY KEY (reviewer_id)
);
CREATE TABLE IF NOT EXISTS mentoring.student_mentor_allotments (
  "mentor_allotment_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "programme_id" bigint,
  "programme_batch_id" bigint,
  "semester_id" bigint,
  "programme_section_id" bigint,
  "allotted_from" date NOT NULL DEFAULT CURRENT_DATE,
  "allotted_to" date,
  "allotment_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  "change_reason" text,
  CONSTRAINT "student_mentor_allotments_pkey" PRIMARY KEY (mentor_allotment_id),
  CONSTRAINT "student_mentor_allotments_check" CHECK (((allotted_to IS NULL) OR (allotted_to >= allotted_from))),
  CONSTRAINT "student_mentor_allotments_allotment_status_check" CHECK (((allotment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Changed'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.mentor_reviewer_allotments (
  "mentor_reviewer_allotment_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "department_id" bigint,
  "mentor_id" bigint NOT NULL,
  "effective_from" date NOT NULL DEFAULT CURRENT_DATE,
  "effective_to" date,
  "allotment_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "remarks" text,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "mentor_reviewer_allotments_pkey" PRIMARY KEY (mentor_reviewer_allotment_id),
  CONSTRAINT "mentor_reviewer_allotments_allotment_status_check" CHECK (((allotment_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
  CONSTRAINT "mentor_reviewer_allotments_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);
CREATE TABLE IF NOT EXISTS mentoring.mentor_reviewer_allotment_details (
  "mentor_reviewer_detail_id" BIGSERIAL NOT NULL,
  "mentor_reviewer_allotment_id" bigint NOT NULL,
  "reviewer_id" bigint NOT NULL,
  "reviewer_role" character varying(20) NOT NULL,
  "display_order" smallint NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "assigned_from" date NOT NULL DEFAULT CURRENT_DATE,
  "assigned_to" date,
  "remarks" text,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "mentor_reviewer_allotment_det_mentor_reviewer_allotment_id__key" UNIQUE (mentor_reviewer_allotment_id, reviewer_role),
  CONSTRAINT "mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_key1" UNIQUE (mentor_reviewer_allotment_id, reviewer_id),
  CONSTRAINT "mentor_reviewer_allotment_details_pkey" PRIMARY KEY (mentor_reviewer_detail_id),
  CONSTRAINT "mentor_reviewer_allotment_details_check" CHECK (((assigned_to IS NULL) OR (assigned_to >= assigned_from))),
  CONSTRAINT "mentor_reviewer_allotment_details_display_order_check" CHECK (((display_order >= 1) AND (display_order <= 3))),
  CONSTRAINT "mentor_reviewer_allotment_details_reviewer_role_check" CHECK (((reviewer_role)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.mentor_reviewer_change_history (
  "mentor_reviewer_change_id" BIGSERIAL NOT NULL,
  "mentor_reviewer_allotment_id" bigint NOT NULL,
  "reviewer_role" character varying(20) NOT NULL,
  "old_reviewer_id" bigint,
  "new_reviewer_id" bigint,
  "effective_date" date NOT NULL DEFAULT CURRENT_DATE,
  "change_reason" text NOT NULL,
  "changed_by" bigint,
  "changed_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "mentor_reviewer_change_history_pkey" PRIMARY KEY (mentor_reviewer_change_id),
  CONSTRAINT "mentor_reviewer_change_history_reviewer_role_check" CHECK (((reviewer_role)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.student_counsellings (
  "student_counselling_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "discussion_date" date NOT NULL DEFAULT CURRENT_DATE,
  "communication_mode" character varying(30) NOT NULL,
  "purpose" character varying(100) NOT NULL,
  "detailed_discussion" text NOT NULL,
  "mentor_remarks" text,
  "follow_up_required" boolean NOT NULL DEFAULT false,
  "next_follow_up_date" date,
  "counselling_status" character varying(20) NOT NULL DEFAULT 'Open'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  "programme_id" bigint,
  "programme_batch_id" bigint,
  "semester_id" bigint,
  "programme_section_id" bigint,
  "communication_mode_id" bigint,
  "counselling_purpose_id" bigint,
  "confidentiality_level" character varying(20) NOT NULL DEFAULT 'Normal'::character varying,
  CONSTRAINT "student_counsellings_pkey" PRIMARY KEY (student_counselling_id),
  CONSTRAINT "student_counsellings_check" CHECK (((next_follow_up_date IS NULL) OR (next_follow_up_date >= discussion_date))),
  CONSTRAINT "student_counsellings_communication_mode_check" CHECK (((communication_mode)::text = ANY (ARRAY[('Over Phone'::character varying)::text, ('Formal Meeting'::character varying)::text, ('Online Meeting'::character varying)::text, ('Parent Meeting'::character varying)::text, ('Email'::character varying)::text, ('WhatsApp'::character varying)::text, ('Home Visit'::character varying)::text, ('Other'::character varying)::text]))),
  CONSTRAINT "student_counsellings_confidentiality_level_check" CHECK (((confidentiality_level)::text = ANY (ARRAY[('Normal'::character varying)::text, ('Restricted'::character varying)::text, ('Confidential'::character varying)::text]))),
  CONSTRAINT "student_counsellings_counselling_status_check" CHECK (((counselling_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Open'::character varying)::text, ('Follow-up'::character varying)::text, ('Resolved'::character varying)::text, ('Closed'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.parent_interactions (
  "parent_interaction_id" BIGSERIAL NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "student_counselling_id" bigint,
  "interaction_date" date NOT NULL DEFAULT CURRENT_DATE,
  "parent_name" character varying(150),
  "relationship" character varying(50),
  "parent_contact_number" character varying(20),
  "communication_mode" character varying(30) NOT NULL,
  "discussion_details" text NOT NULL,
  "parent_commitment" text,
  "action_required" text,
  "next_contact_date" date,
  "interaction_status" character varying(20) NOT NULL DEFAULT 'Completed'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "parent_interactions_pkey" PRIMARY KEY (parent_interaction_id),
  CONSTRAINT "parent_interactions_check" CHECK (((next_contact_date IS NULL) OR (next_contact_date >= interaction_date))),
  CONSTRAINT "parent_interactions_communication_mode_check" CHECK (((communication_mode)::text = ANY (ARRAY[('Over Phone'::character varying)::text, ('Formal Meeting'::character varying)::text, ('Online Meeting'::character varying)::text, ('Email'::character varying)::text, ('WhatsApp'::character varying)::text, ('Other'::character varying)::text]))),
  CONSTRAINT "parent_interactions_interaction_status_check" CHECK (((interaction_status)::text = ANY (ARRAY[('Scheduled'::character varying)::text, ('Completed'::character varying)::text, ('Follow-up'::character varying)::text, ('Cancelled'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.counselling_followups (
  "counselling_followup_id" BIGSERIAL NOT NULL,
  "student_counselling_id" bigint NOT NULL,
  "followup_date" date NOT NULL DEFAULT CURRENT_DATE,
  "followup_type" character varying(30) NOT NULL,
  "followup_details" text NOT NULL,
  "action_taken" text,
  "assigned_to_employee_id" bigint,
  "next_followup_date" date,
  "followup_status" character varying(20) NOT NULL DEFAULT 'Pending'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "counselling_followups_followup_status_check" CHECK (((followup_status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('In Progress'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
  CONSTRAINT "counselling_followups_followup_type_check" CHECK (((followup_type)::text = ANY (ARRAY[('Mentor Follow-up'::character varying)::text, ('Reviewer Follow-up'::character varying)::text, ('Parent Contact'::character varying)::text, ('Academic Support'::character varying)::text, ('Attendance Warning'::character varying)::text, ('Other'::character varying)::text]))),
  CONSTRAINT "counselling_followups_check" CHECK (((next_followup_date IS NULL) OR (next_followup_date >= followup_date))),
  CONSTRAINT "counselling_followups_pkey" PRIMARY KEY (counselling_followup_id)
);
CREATE TABLE IF NOT EXISTS mentoring.counselling_reviewer_remarks (
  "counselling_reviewer_remark_id" BIGSERIAL NOT NULL,
  "student_counselling_id" bigint NOT NULL,
  "reviewer_id" bigint NOT NULL,
  "reviewer_level" character varying(20) NOT NULL,
  "review_date" date NOT NULL DEFAULT CURRENT_DATE,
  "reviewer_remarks" text NOT NULL,
  "recommendation" text,
  "follow_up_required" boolean NOT NULL DEFAULT false,
  "next_review_date" date,
  "review_status" character varying(20) NOT NULL DEFAULT 'Draft'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "counselling_reviewer_remarks_pkey" PRIMARY KEY (counselling_reviewer_remark_id),
  CONSTRAINT "counselling_reviewer_remarks_student_counselling_id_reviewe_key" UNIQUE (student_counselling_id, reviewer_level),
  CONSTRAINT "counselling_reviewer_remarks_check" CHECK (((next_review_date IS NULL) OR (next_review_date >= review_date))),
  CONSTRAINT "counselling_reviewer_remarks_review_status_check" CHECK (((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text, ('Closed'::character varying)::text]))),
  CONSTRAINT "counselling_reviewer_remarks_reviewer_level_check" CHECK (((reviewer_level)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.first_reviewer_remarks (
  "first_reviewer_remark_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "reviewer_id" bigint NOT NULL,
  "mentor_reviewer_allotment_id" bigint,
  "review_date" date NOT NULL DEFAULT CURRENT_DATE,
  "information_entered" text,
  "first_reviewer_remarks" text NOT NULL,
  "grading_to_mentor" character varying(30),
  "suggestion_to_mentor" text,
  "follow_up_required" boolean NOT NULL DEFAULT false,
  "next_review_date" date,
  "review_status" character varying(20) NOT NULL DEFAULT 'Draft'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "first_reviewer_remarks_pkey" PRIMARY KEY (first_reviewer_remark_id),
  CONSTRAINT "first_reviewer_remarks_check" CHECK (((next_review_date IS NULL) OR (next_review_date >= review_date))),
  CONSTRAINT "first_reviewer_remarks_grading_to_mentor_check" CHECK (((grading_to_mentor IS NULL) OR ((grading_to_mentor)::text = ANY (ARRAY[('Excellent'::character varying)::text, ('Very Good'::character varying)::text, ('Good'::character varying)::text, ('Average'::character varying)::text, ('Needs Improvement'::character varying)::text, ('Unsatisfactory'::character varying)::text])))),
  CONSTRAINT "first_reviewer_remarks_review_status_check" CHECK (((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text, ('Closed'::character varying)::text])))
);
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility'::regclass AND conname='employee_mentor_eligibility_created_by_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility ADD CONSTRAINT "employee_mentor_eligibility_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility'::regclass AND conname='employee_mentor_eligibility_employee_id_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility ADD CONSTRAINT "employee_mentor_eligibility_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility'::regclass AND conname='employee_mentor_eligibility_updated_by_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility ADD CONSTRAINT "employee_mentor_eligibility_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.employee_mentor_eligibility') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility_history'::regclass AND conname='employee_mentor_eligibility_h_employee_mentor_eligibility__fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility_history ADD CONSTRAINT "employee_mentor_eligibility_h_employee_mentor_eligibility__fkey" FOREIGN KEY (employee_mentor_eligibility_id) REFERENCES mentoring.employee_mentor_eligibility(employee_mentor_eligibility_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility_history'::regclass AND conname='employee_mentor_eligibility_history_changed_by_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility_history ADD CONSTRAINT "employee_mentor_eligibility_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.employee_mentor_eligibility') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='fk_mentor_employee_eligibility') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "fk_mentor_employee_eligibility" FOREIGN KEY (employee_mentor_eligibility_id) REFERENCES mentoring.employee_mentor_eligibility(employee_mentor_eligibility_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_created_by_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('departments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_department_id_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_department_id_fkey" FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_employee_id_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_updated_by_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.reviewers'::regclass AND conname='reviewers_employee_id_fkey') THEN ALTER TABLE mentoring.reviewers ADD CONSTRAINT "reviewers_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_academic_year_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_created_by_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_mentor_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('admission_batches') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_programme_batch_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_programme_batch_id_fkey" FOREIGN KEY (programme_batch_id) REFERENCES admission_batches(batch_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('programmes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_programme_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_programme_id_fkey" FOREIGN KEY (programme_id) REFERENCES programmes(programme_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('sections') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_programme_section_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_programme_section_id_fkey" FOREIGN KEY (programme_section_id) REFERENCES sections(section_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('semesters') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_semester_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_semester_id_fkey" FOREIGN KEY (semester_id) REFERENCES semesters(semester_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_student_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_updated_by_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_academic_year_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_created_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('departments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_department_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_department_id_fkey" FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_mentor_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_updated_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentor_reviewer_allotments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotment_details'::regclass AND conname='mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotment_details ADD CONSTRAINT "mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_fkey" FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotment_details'::regclass AND conname='mentor_reviewer_allotment_details_created_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotment_details ADD CONSTRAINT "mentor_reviewer_allotment_details_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotment_details'::regclass AND conname='mentor_reviewer_allotment_details_reviewer_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotment_details ADD CONSTRAINT "mentor_reviewer_allotment_details_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentor_reviewer_allotments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_histor_mentor_reviewer_allotment_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_histor_mentor_reviewer_allotment_id_fkey" FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_history_changed_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_history_new_reviewer_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_history_new_reviewer_id_fkey" FOREIGN KEY (new_reviewer_id) REFERENCES employees(employee_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_history_old_reviewer_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_history_old_reviewer_id_fkey" FOREIGN KEY (old_reviewer_id) REFERENCES employees(employee_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_academic_year_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.communication_modes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_communication_mode_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_communication_mode_id_fkey" FOREIGN KEY (communication_mode_id) REFERENCES mentoring.communication_modes(communication_mode_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.counselling_purposes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_counselling_purpose_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_counselling_purpose_id_fkey" FOREIGN KEY (counselling_purpose_id) REFERENCES mentoring.counselling_purposes(counselling_purpose_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_created_by_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_mentor_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('admission_batches') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_programme_batch_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_programme_batch_id_fkey" FOREIGN KEY (programme_batch_id) REFERENCES admission_batches(batch_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('programmes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_programme_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_programme_id_fkey" FOREIGN KEY (programme_id) REFERENCES programmes(programme_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('sections') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_programme_section_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_programme_section_id_fkey" FOREIGN KEY (programme_section_id) REFERENCES sections(section_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('semesters') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_semester_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_semester_id_fkey" FOREIGN KEY (semester_id) REFERENCES semesters(semester_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_student_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_updated_by_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_created_by_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_mentor_id_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.student_counsellings') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_student_counselling_id_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_student_counselling_id_fkey" FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_student_id_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_updated_by_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_followups'::regclass AND conname='counselling_followups_assigned_to_employee_id_fkey') THEN ALTER TABLE mentoring.counselling_followups ADD CONSTRAINT "counselling_followups_assigned_to_employee_id_fkey" FOREIGN KEY (assigned_to_employee_id) REFERENCES employees(employee_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_followups'::regclass AND conname='counselling_followups_created_by_fkey') THEN ALTER TABLE mentoring.counselling_followups ADD CONSTRAINT "counselling_followups_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.student_counsellings') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_followups'::regclass AND conname='counselling_followups_student_counselling_id_fkey') THEN ALTER TABLE mentoring.counselling_followups ADD CONSTRAINT "counselling_followups_student_counselling_id_fkey" FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_created_by_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_reviewer_id_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.student_counsellings') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_student_counselling_id_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_student_counselling_id_fkey" FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_updated_by_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_academic_year_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_created_by_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_mentor_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentor_reviewer_allotments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_mentor_reviewer_allotment_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_mentor_reviewer_allotment_id_fkey" FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_reviewer_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_student_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_updated_by_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;

CREATE TABLE IF NOT EXISTS mentoring.mentor_assignment_changes (
  assignment_change_id BIGSERIAL PRIMARY KEY,
  student_id BIGINT NOT NULL REFERENCES public.students(student_id) ON DELETE CASCADE,
  academic_year_id BIGINT NOT NULL REFERENCES public.academic_years(academic_year_id),
  previous_mentor_id BIGINT REFERENCES mentoring.mentors(mentor_id),
  mentor_id BIGINT NOT NULL REFERENCES mentoring.mentors(mentor_id),
  changed_by BIGINT REFERENCES public.users(user_id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mentor_assignment_changes_student ON mentoring.mentor_assignment_changes(student_id,changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_mentor_activity_student_date ON mentoring.student_counsellings(student_id,discussion_date);
CREATE INDEX IF NOT EXISTS idx_mentor_parent_activity_student_date ON mentoring.parent_interactions(student_id,interaction_date);


-- Hide replaced submenu entries while preserving their permission history.
UPDATE permission_management.system_menus SET status=FALSE WHERE menu_code IN ('MENTORING_MENU_1ST_REVIEWER_REMARKS','MENTORING_MENU_FIRST_REVIEWER_REMARKS','MENTORING_MENU_MENTOR_ACTIVITY','MENTOR_ALLOTMENT_MENU_EXISTING_STUDENT','MENTOR_ALLOTMENT_MENU_PROSPECTIVE_STUDENT','MENTOR_ALLOTMENT_MENU_MENTOR_ALLOTMENT_REPORT');
UPDATE permission_management.system_menus SET display_order=CASE menu_code WHEN 'MENTORING_MENU_REVIEWER_ALLOTMENT' THEN 1 WHEN 'MENTORING_MENU_ALL_COUNSELLING_AND_REVIEWS' THEN 2 WHEN 'MENTOR_ACTIVITY' THEN 3 ELSE display_order END WHERE menu_code IN ('MENTORING_MENU_REVIEWER_ALLOTMENT','MENTORING_MENU_ALL_COUNSELLING_AND_REVIEWS','MENTOR_ACTIVITY');

WITH eligible AS (
  SELECT st.student_id,MIN(s.section_id) AS section_id,MIN(s.semester_id) AS semester_id
  FROM students st
  JOIN batch_section_assignments a ON a.batch_id=st.batch_id AND a.is_active=TRUE
  JOIN sections s ON s.section_id=a.initial_section_id AND s.batch_id=st.batch_id AND s.is_active=TRUE
  JOIN semesters se ON se.semester_id=s.semester_id AND se.programme_id=st.programme_id
  WHERE st.section_id IS NULL AND COALESCE(st.is_deleted,FALSE)=FALSE
    AND (st.semester_id IS NULL OR st.semester_id=s.semester_id)
  GROUP BY st.student_id HAVING COUNT(DISTINCT s.section_id)=1
)
UPDATE students st SET section_id=e.section_id,semester_id=COALESCE(st.semester_id,e.semester_id),
  student_profile_details=st.student_profile_details||jsonb_build_object('sectionId',e.section_id::text,'semesterId',e.semester_id::text),updated_at=NOW()
FROM eligible e WHERE st.student_id=e.student_id;

-- Semester Promotion / Define Semester uses public.programme_semester_definitions above.
CREATE INDEX IF NOT EXISTS idx_semester_promotion_active_batch ON public.programme_semester_definitions(programme_batch_id,is_active,semester_id);

-- Link active Define Semester settings to batch sections.
INSERT INTO sections
  (batch_id,semester_id,term_id,section_name,strength_limit,section_master_id,is_active)
SELECT d.programme_batch_id,d.semester_id,initial.term_id,sm.section_master_name,a.intake,a.section_master_id,TRUE
FROM programme_semester_definitions d
JOIN semesters se ON se.semester_id=d.semester_id AND se.programme_id=d.course_id AND se.is_active=TRUE
JOIN admission_batches b ON b.batch_id=d.programme_batch_id AND b.programme_id=d.course_id AND b.is_active=TRUE
JOIN batch_section_assignments a ON a.batch_id=d.programme_batch_id AND a.is_active=TRUE
JOIN section_masters sm ON sm.section_master_id=a.section_master_id AND sm.is_active=TRUE
JOIN sections initial ON initial.section_id=a.initial_section_id AND initial.is_active=TRUE
WHERE d.is_active=TRUE AND d.class_type='SECTION'
  AND NOT EXISTS(SELECT 1 FROM sections s WHERE s.batch_id=d.programme_batch_id AND s.semester_id=d.semester_id AND s.section_master_id=a.section_master_id)
ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.class_teacher_allocations (
 class_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_id BIGINT NOT NULL REFERENCES programmes(programme_id),
 batch_id BIGINT NOT NULL REFERENCES admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 section_id BIGINT NOT NULL REFERENCES sections(section_id),
 student_group VARCHAR(30) NOT NULL DEFAULT 'ALL',
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 teacher_type VARCHAR(20) NOT NULL DEFAULT 'MAIN',
 status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
 created_by BIGINT REFERENCES users(user_id),created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_by BIGINT REFERENCES users(user_id),updated_at TIMESTAMPTZ
);
ALTER TABLE public.class_teacher_allocations ADD COLUMN IF NOT EXISTS subject_master_id BIGINT REFERENCES subject_masters(subject_master_id);
DO $class_subject$ DECLARE item RECORD; BEGIN
 FOR item IN SELECT conname FROM pg_constraint WHERE conrelid='public.class_teacher_allocations'::regclass AND contype='u' AND (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM unnest(conkey) AS key(attnum) JOIN pg_attribute a ON a.attrelid=conrelid AND a.attnum=key.attnum)=ARRAY['academic_year_id','batch_id','section_id','semester_id','student_group']::text[] LOOP
 EXECUTE format('ALTER TABLE public.class_teacher_allocations DROP CONSTRAINT %I',item.conname);
 END LOOP;
END $class_subject$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_class_subject_teacher_role ON public.class_teacher_allocations(academic_year_id,batch_id,semester_id,section_id,student_group,subject_master_id,teacher_type) WHERE subject_master_id IS NOT NULL AND status='ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS uq_legacy_class_teacher ON public.class_teacher_allocations(academic_year_id,batch_id,semester_id,section_id,student_group) WHERE subject_master_id IS NULL AND status='ACTIVE';
CREATE INDEX IF NOT EXISTS idx_class_teacher_subject ON public.class_teacher_allocations(subject_master_id);

INSERT INTO mentoring.counselling_purposes(purpose_code,purpose_name,is_active) VALUES
 ('NORMAL_CLASS','Normal Class',TRUE),
 ('SHORT_ATTENDANCE','Short Attendance',TRUE),
 ('ADDRESS','Address',TRUE),
 ('OTHER','Other',TRUE),
 ('INTERNAL_EXAMINATION','Internal Examination',TRUE),
 ('SEMESTER_RESULT','Semester Result',TRUE),
 ('FATHER_CONTACT_NO','Father Contact No',TRUE)
ON CONFLICT(purpose_code) DO UPDATE SET purpose_name=EXCLUDED.purpose_name,is_active=TRUE;
UPDATE mentoring.student_counsellings sc SET counselling_purpose_id=p.counselling_purpose_id
FROM mentoring.counselling_purposes p WHERE sc.counselling_purpose_id IS NULL AND LOWER(TRIM(sc.purpose))=LOWER(p.purpose_name);

COMMIT;

ABDC_SOURCE_END server/ABDC_ERP_Complete_Database.sql */

/* ABDC_SOURCE_BEGIN server/batch-management.sql SHA256 60afb2b554edf62f45ec5214dff1f0709907607b8bc27b0e6bc8589709b2fa56
BEGIN;
-- Shared batch master used by Course > Batch and academic allocations.
CREATE TABLE IF NOT EXISTS public.admission_batches (
  batch_id BIGSERIAL PRIMARY KEY,
  programme_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  admission_year SMALLINT NOT NULL,
  batch_name VARCHAR(100) NOT NULL,
  batch_alias VARCHAR(50),
  start_date DATE,
  expected_end_date DATE,
  approved_intake INTEGER NOT NULL DEFAULT 0,
  lateral_entry_intake INTEGER NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(programme_id,admission_year)
);
CREATE TABLE IF NOT EXISTS public.batch_survey_settings (
  batch_id BIGINT PRIMARY KEY REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE,
  annual_survey_eligible BOOLEAN NOT NULL DEFAULT FALSE,
  exit_survey_eligible BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMIT;

ABDC_SOURCE_END server/batch-management.sql */

/* ABDC_SOURCE_BEGIN server/class-teacher-subjects.sql SHA256 bfad5abf9926a3c056d014945597d8aa96952555863c23c92d3f9f313eb68507
BEGIN;
CREATE TABLE IF NOT EXISTS public.class_teacher_allocations (
 class_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_id BIGINT NOT NULL REFERENCES programmes(programme_id),
 batch_id BIGINT NOT NULL REFERENCES admission_batches(batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 section_id BIGINT NOT NULL REFERENCES sections(section_id),
 student_group VARCHAR(30) NOT NULL DEFAULT 'ALL',
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 teacher_type VARCHAR(20) NOT NULL DEFAULT 'MAIN',
 status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
 created_by BIGINT REFERENCES users(user_id),created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_by BIGINT REFERENCES users(user_id),updated_at TIMESTAMPTZ
);
ALTER TABLE public.class_teacher_allocations ADD COLUMN IF NOT EXISTS subject_master_id BIGINT REFERENCES subject_masters(subject_master_id);
DO $class_subject$ DECLARE item RECORD; BEGIN
 FOR item IN SELECT conname FROM pg_constraint WHERE conrelid='public.class_teacher_allocations'::regclass AND contype='u' AND (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM unnest(conkey) AS key(attnum) JOIN pg_attribute a ON a.attrelid=conrelid AND a.attnum=key.attnum)=ARRAY['academic_year_id','batch_id','section_id','semester_id','student_group']::text[] LOOP
 EXECUTE format('ALTER TABLE public.class_teacher_allocations DROP CONSTRAINT %I',item.conname);
 END LOOP;
END $class_subject$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_class_subject_teacher_role ON public.class_teacher_allocations(academic_year_id,batch_id,semester_id,section_id,student_group,subject_master_id,teacher_type) WHERE subject_master_id IS NOT NULL AND status='ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS uq_legacy_class_teacher ON public.class_teacher_allocations(academic_year_id,batch_id,semester_id,section_id,student_group) WHERE subject_master_id IS NULL AND status='ACTIVE';
CREATE INDEX IF NOT EXISTS idx_class_teacher_subject ON public.class_teacher_allocations(subject_master_id);
COMMIT;

ABDC_SOURCE_END server/class-teacher-subjects.sql */

/* ABDC_SOURCE_BEGIN server/college_programmes.sql SHA256 0224dd99318a60a73ddfdc2d2d83957b8d54f75753e35f5ca282c8f98710ec2a
BEGIN;
-- Add the existing college departments as programmes without changing BCA.
-- New programmes follow the current BCA duration and semester structure.
DO $college$
DECLARE source RECORD; department RECORD; programme_id_new BIGINT; number INTEGER; semester_count INTEGER; columns_sql TEXT; values_sql TEXT;
BEGIN
  SELECT p.*,d.institution_id INTO source FROM public.programmes p
    JOIN public.departments d ON d.department_id=p.department_id
    WHERE UPPER(p.programme_code)='BCA' AND p.is_active ORDER BY p.programme_id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'An active BCA programme is required as the college programme template.'; END IF;
  SELECT MAX(semester_number) INTO semester_count FROM public.semesters WHERE programme_id=source.programme_id;
  IF semester_count IS NULL THEN RAISE EXCEPTION 'Configure BCA semesters before adding the other college programmes.'; END IF;
  FOR department IN SELECT * FROM public.departments
    WHERE institution_id=source.institution_id AND is_active AND department_code IN ('BBA','B.Sc ITM')
  LOOP
    IF EXISTS(SELECT 1 FROM public.programmes WHERE department_id=department.department_id AND UPPER(programme_code)=UPPER(department.department_code)) THEN CONTINUE; END IF;
    columns_sql='department_id,programme_code,programme_name,programme_level,duration_years,is_active';
    values_sql='$1,$2,$3,$4,$5,TRUE';
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='programmes' AND column_name='institution_id') THEN
      columns_sql=columns_sql||',institution_id'; values_sql=values_sql||',$6';
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='programmes' AND column_name='total_semesters') THEN
      columns_sql=columns_sql||',total_semesters'; values_sql=values_sql||',$7';
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='programmes' AND column_name='duration_semesters') THEN
      columns_sql=columns_sql||',duration_semesters'; values_sql=values_sql||',$7';
    END IF;
    EXECUTE 'INSERT INTO public.programmes('||columns_sql||') VALUES('||values_sql||') RETURNING programme_id'
      INTO programme_id_new USING department.department_id,department.department_code,department.department_name,source.programme_level,source.duration_years,source.institution_id,semester_count;
    FOR number IN 1..semester_count LOOP
      INSERT INTO public.semesters(programme_id,semester_number,semester_name,is_active)
        VALUES(programme_id_new,number,'Semester '||number,TRUE);
      IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='semesters' AND column_name='year_number') THEN
        EXECUTE 'UPDATE public.semesters SET year_number=$1 WHERE programme_id=$2 AND semester_number=$3' USING (number+1)/2,programme_id_new,number;
      END IF;
    END LOOP;
  END LOOP;
END $college$;
COMMIT;

ABDC_SOURCE_END server/college_programmes.sql */

/* ABDC_SOURCE_BEGIN server/counselling-purposes.sql SHA256 6a3241bd8cd617f1d79b50d6bd5c39005f2b0b335bd7b0f2504f995ac85d6dc7
BEGIN;
INSERT INTO mentoring.counselling_purposes(purpose_code,purpose_name,is_active) VALUES
 ('NORMAL_CLASS','Normal Class',TRUE),
 ('SHORT_ATTENDANCE','Short Attendance',TRUE),
 ('ADDRESS','Address',TRUE),
 ('OTHER','Other',TRUE),
 ('INTERNAL_EXAMINATION','Internal Examination',TRUE),
 ('SEMESTER_RESULT','Semester Result',TRUE),
 ('FATHER_CONTACT_NO','Father Contact No',TRUE)
ON CONFLICT(purpose_code) DO UPDATE SET purpose_name=EXCLUDED.purpose_name,is_active=TRUE;
UPDATE mentoring.student_counsellings sc SET counselling_purpose_id=p.counselling_purpose_id
FROM mentoring.counselling_purposes p WHERE sc.counselling_purpose_id IS NULL AND LOWER(TRIM(sc.purpose))=LOWER(p.purpose_name);
COMMIT;

ABDC_SOURCE_END server/counselling-purposes.sql */

/* ABDC_SOURCE_BEGIN server/course-management.sql SHA256 b9b70caa9c31e0dd604b7a4240e1fff57c00a7d29d05c435bbe2ee3ae8947f14
BEGIN;
-- Course fields are stored in the shared programmes, batches and sections tables.
ALTER TABLE public.programmes
  ADD COLUMN IF NOT EXISTS programme_alias VARCHAR(100),
  ADD COLUMN IF NOT EXISTS programme_type VARCHAR(40) NOT NULL DEFAULT 'UNDERGRADUATE',
  ADD COLUMN IF NOT EXISTS total_semesters INTEGER NOT NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS award_type VARCHAR(40) NOT NULL DEFAULT 'DEGREE',
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE public.admission_batches
  ADD COLUMN IF NOT EXISTS batch_alias VARCHAR(50),
  ADD COLUMN IF NOT EXISTS admission_year INTEGER,
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS expected_end_date DATE,
  ADD COLUMN IF NOT EXISTS approved_intake INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lateral_entry_intake INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE public.admission_batches ALTER COLUMN batch_name TYPE VARCHAR(100);
ALTER TABLE public.sections ALTER COLUMN section_name TYPE VARCHAR(100);
ALTER TABLE public.semesters ADD COLUMN IF NOT EXISTS year_number INTEGER;
ALTER TABLE public.sections ADD COLUMN IF NOT EXISTS strength_limit INTEGER;

-- programmes remains the shared course master used by subjects and allocations.
-- Store the initial batch and section created by the compact Course form.
CREATE TABLE IF NOT EXISTS public.course_initial_setup (
  course_id BIGINT PRIMARY KEY REFERENCES public.programmes(programme_id) ON DELETE CASCADE,
  batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE,
  section_id BIGINT NOT NULL REFERENCES public.sections(section_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS course_initial_setup_batch_idx ON public.course_initial_setup(batch_id);
COMMIT;

ABDC_SOURCE_END server/course-management.sql */

/* ABDC_SOURCE_BEGIN server/defined-semester-sections.sql SHA256 919042af97fe392e5f924e1071fd7c602976216584826144c74f99383fef2d7c
BEGIN;
INSERT INTO sections
  (batch_id,semester_id,term_id,section_name,strength_limit,section_master_id,is_active)
SELECT d.programme_batch_id,d.semester_id,initial.term_id,sm.section_master_name,a.intake,a.section_master_id,TRUE
FROM programme_semester_definitions d
JOIN semesters se ON se.semester_id=d.semester_id AND se.programme_id=d.course_id AND se.is_active=TRUE
JOIN admission_batches b ON b.batch_id=d.programme_batch_id AND b.programme_id=d.course_id AND b.is_active=TRUE
JOIN batch_section_assignments a ON a.batch_id=d.programme_batch_id AND a.is_active=TRUE
JOIN section_masters sm ON sm.section_master_id=a.section_master_id AND sm.is_active=TRUE
JOIN sections initial ON initial.section_id=a.initial_section_id AND initial.is_active=TRUE
WHERE d.is_active=TRUE AND d.class_type='SECTION'
  AND NOT EXISTS(SELECT 1 FROM sections s WHERE s.batch_id=d.programme_batch_id AND s.semester_id=d.semester_id AND s.section_master_id=a.section_master_id)
ON CONFLICT DO NOTHING;
COMMIT;

ABDC_SOURCE_END server/defined-semester-sections.sql */

/* ABDC_SOURCE_BEGIN server/employee-edit.sql SHA256 1b57002ad3e81cc6070e25e21339dafcb9ef2a296a0664d319b0e746c39b3fc4
BEGIN;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS profile_details JSONB NOT NULL DEFAULT '{}'::jsonb;
COMMIT;

ABDC_SOURCE_END server/employee-edit.sql */

/* ABDC_SOURCE_BEGIN server/mentoring-redesign.sql SHA256 c75abc6ca8a1f488f4a84d980aafa5896c3b229f5f326feede81dacba69f821e
BEGIN;
CREATE SCHEMA IF NOT EXISTS mentoring;
-- Tables used by Reviewer Allotment, Counselling & Reviews, Mentor Activity and Mentor Assignment.
CREATE TABLE IF NOT EXISTS mentoring.communication_modes (
  "communication_mode_id" BIGSERIAL NOT NULL,
  "mode_code" character varying(30) NOT NULL,
  "mode_name" character varying(100) NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "communication_modes_mode_code_key" UNIQUE (mode_code),
  CONSTRAINT "communication_modes_mode_name_key" UNIQUE (mode_name),
  CONSTRAINT "communication_modes_pkey" PRIMARY KEY (communication_mode_id)
);
CREATE TABLE IF NOT EXISTS mentoring.counselling_purposes (
  "counselling_purpose_id" BIGSERIAL NOT NULL,
  "purpose_code" character varying(30) NOT NULL,
  "purpose_name" character varying(100) NOT NULL,
  "description" text,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "counselling_purposes_pkey" PRIMARY KEY (counselling_purpose_id),
  CONSTRAINT "counselling_purposes_purpose_code_key" UNIQUE (purpose_code),
  CONSTRAINT "counselling_purposes_purpose_name_key" UNIQUE (purpose_name)
);
CREATE TABLE IF NOT EXISTS mentoring.employee_mentor_eligibility (
  "employee_mentor_eligibility_id" BIGSERIAL NOT NULL,
  "employee_id" bigint NOT NULL,
  "is_mentor_for_new_students" boolean NOT NULL DEFAULT false,
  "maximum_students" integer NOT NULL DEFAULT 30,
  "effective_from" date NOT NULL DEFAULT CURRENT_DATE,
  "effective_to" date,
  "eligibility_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "remarks" text,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "employee_mentor_eligibility_employee_id_key" UNIQUE (employee_id),
  CONSTRAINT "employee_mentor_eligibility_pkey" PRIMARY KEY (employee_mentor_eligibility_id),
  CONSTRAINT "employee_mentor_eligibility_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from))),
  CONSTRAINT "employee_mentor_eligibility_eligibility_status_check" CHECK (((eligibility_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Suspended'::character varying)::text]))),
  CONSTRAINT "employee_mentor_eligibility_maximum_students_check" CHECK ((maximum_students > 0))
);
CREATE TABLE IF NOT EXISTS mentoring.employee_mentor_eligibility_history (
  "employee_mentor_eligibility_history_id" BIGSERIAL NOT NULL,
  "employee_mentor_eligibility_id" bigint NOT NULL,
  "old_is_mentor" boolean,
  "new_is_mentor" boolean NOT NULL,
  "old_maximum_students" integer,
  "new_maximum_students" integer,
  "change_reason" text,
  "changed_by" bigint,
  "changed_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "employee_mentor_eligibility_history_pkey" PRIMARY KEY (employee_mentor_eligibility_history_id)
);
CREATE TABLE IF NOT EXISTS mentoring.mentors (
  "mentor_id" BIGSERIAL NOT NULL,
  "employee_id" bigint NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "department_id" bigint,
  "maximum_students" integer NOT NULL DEFAULT 30,
  "mentor_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "created_by" bigint,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  "employee_mentor_eligibility_id" bigint,
  "effective_from" date NOT NULL DEFAULT CURRENT_DATE,
  "effective_to" date,
  CONSTRAINT "mentors_employee_id_key" UNIQUE (employee_id),
  CONSTRAINT "mentors_pkey" PRIMARY KEY (mentor_id),
  CONSTRAINT "mentors_effective_dates_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);
CREATE TABLE IF NOT EXISTS mentoring.reviewers (
  "reviewer_id" BIGSERIAL NOT NULL,
  "employee_id" bigint NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "reviewers_employee_id_key" UNIQUE (employee_id),
  CONSTRAINT "reviewers_pkey" PRIMARY KEY (reviewer_id)
);
CREATE TABLE IF NOT EXISTS mentoring.student_mentor_allotments (
  "mentor_allotment_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "programme_id" bigint,
  "programme_batch_id" bigint,
  "semester_id" bigint,
  "programme_section_id" bigint,
  "allotted_from" date NOT NULL DEFAULT CURRENT_DATE,
  "allotted_to" date,
  "allotment_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  "change_reason" text,
  CONSTRAINT "student_mentor_allotments_pkey" PRIMARY KEY (mentor_allotment_id),
  CONSTRAINT "student_mentor_allotments_check" CHECK (((allotted_to IS NULL) OR (allotted_to >= allotted_from))),
  CONSTRAINT "student_mentor_allotments_allotment_status_check" CHECK (((allotment_status)::text = ANY (ARRAY[('Active'::character varying)::text, ('Changed'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.mentor_reviewer_allotments (
  "mentor_reviewer_allotment_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "department_id" bigint,
  "mentor_id" bigint NOT NULL,
  "effective_from" date NOT NULL DEFAULT CURRENT_DATE,
  "effective_to" date,
  "allotment_status" character varying(20) NOT NULL DEFAULT 'Active'::character varying,
  "remarks" text,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "mentor_reviewer_allotments_pkey" PRIMARY KEY (mentor_reviewer_allotment_id),
  CONSTRAINT "mentor_reviewer_allotments_allotment_status_check" CHECK (((allotment_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Active'::character varying)::text, ('Inactive'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
  CONSTRAINT "mentor_reviewer_allotments_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);
CREATE TABLE IF NOT EXISTS mentoring.mentor_reviewer_allotment_details (
  "mentor_reviewer_detail_id" BIGSERIAL NOT NULL,
  "mentor_reviewer_allotment_id" bigint NOT NULL,
  "reviewer_id" bigint NOT NULL,
  "reviewer_role" character varying(20) NOT NULL,
  "display_order" smallint NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "assigned_from" date NOT NULL DEFAULT CURRENT_DATE,
  "assigned_to" date,
  "remarks" text,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "mentor_reviewer_allotment_det_mentor_reviewer_allotment_id__key" UNIQUE (mentor_reviewer_allotment_id, reviewer_role),
  CONSTRAINT "mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_key1" UNIQUE (mentor_reviewer_allotment_id, reviewer_id),
  CONSTRAINT "mentor_reviewer_allotment_details_pkey" PRIMARY KEY (mentor_reviewer_detail_id),
  CONSTRAINT "mentor_reviewer_allotment_details_check" CHECK (((assigned_to IS NULL) OR (assigned_to >= assigned_from))),
  CONSTRAINT "mentor_reviewer_allotment_details_display_order_check" CHECK (((display_order >= 1) AND (display_order <= 3))),
  CONSTRAINT "mentor_reviewer_allotment_details_reviewer_role_check" CHECK (((reviewer_role)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.mentor_reviewer_change_history (
  "mentor_reviewer_change_id" BIGSERIAL NOT NULL,
  "mentor_reviewer_allotment_id" bigint NOT NULL,
  "reviewer_role" character varying(20) NOT NULL,
  "old_reviewer_id" bigint,
  "new_reviewer_id" bigint,
  "effective_date" date NOT NULL DEFAULT CURRENT_DATE,
  "change_reason" text NOT NULL,
  "changed_by" bigint,
  "changed_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "mentor_reviewer_change_history_pkey" PRIMARY KEY (mentor_reviewer_change_id),
  CONSTRAINT "mentor_reviewer_change_history_reviewer_role_check" CHECK (((reviewer_role)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.student_counsellings (
  "student_counselling_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "discussion_date" date NOT NULL DEFAULT CURRENT_DATE,
  "communication_mode" character varying(30) NOT NULL,
  "purpose" character varying(100) NOT NULL,
  "detailed_discussion" text NOT NULL,
  "mentor_remarks" text,
  "follow_up_required" boolean NOT NULL DEFAULT false,
  "next_follow_up_date" date,
  "counselling_status" character varying(20) NOT NULL DEFAULT 'Open'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  "programme_id" bigint,
  "programme_batch_id" bigint,
  "semester_id" bigint,
  "programme_section_id" bigint,
  "communication_mode_id" bigint,
  "counselling_purpose_id" bigint,
  "confidentiality_level" character varying(20) NOT NULL DEFAULT 'Normal'::character varying,
  CONSTRAINT "student_counsellings_pkey" PRIMARY KEY (student_counselling_id),
  CONSTRAINT "student_counsellings_check" CHECK (((next_follow_up_date IS NULL) OR (next_follow_up_date >= discussion_date))),
  CONSTRAINT "student_counsellings_communication_mode_check" CHECK (((communication_mode)::text = ANY (ARRAY[('Over Phone'::character varying)::text, ('Formal Meeting'::character varying)::text, ('Online Meeting'::character varying)::text, ('Parent Meeting'::character varying)::text, ('Email'::character varying)::text, ('WhatsApp'::character varying)::text, ('Home Visit'::character varying)::text, ('Other'::character varying)::text]))),
  CONSTRAINT "student_counsellings_confidentiality_level_check" CHECK (((confidentiality_level)::text = ANY (ARRAY[('Normal'::character varying)::text, ('Restricted'::character varying)::text, ('Confidential'::character varying)::text]))),
  CONSTRAINT "student_counsellings_counselling_status_check" CHECK (((counselling_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Open'::character varying)::text, ('Follow-up'::character varying)::text, ('Resolved'::character varying)::text, ('Closed'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.parent_interactions (
  "parent_interaction_id" BIGSERIAL NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "student_counselling_id" bigint,
  "interaction_date" date NOT NULL DEFAULT CURRENT_DATE,
  "parent_name" character varying(150),
  "relationship" character varying(50),
  "parent_contact_number" character varying(20),
  "communication_mode" character varying(30) NOT NULL,
  "discussion_details" text NOT NULL,
  "parent_commitment" text,
  "action_required" text,
  "next_contact_date" date,
  "interaction_status" character varying(20) NOT NULL DEFAULT 'Completed'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "parent_interactions_pkey" PRIMARY KEY (parent_interaction_id),
  CONSTRAINT "parent_interactions_check" CHECK (((next_contact_date IS NULL) OR (next_contact_date >= interaction_date))),
  CONSTRAINT "parent_interactions_communication_mode_check" CHECK (((communication_mode)::text = ANY (ARRAY[('Over Phone'::character varying)::text, ('Formal Meeting'::character varying)::text, ('Online Meeting'::character varying)::text, ('Email'::character varying)::text, ('WhatsApp'::character varying)::text, ('Other'::character varying)::text]))),
  CONSTRAINT "parent_interactions_interaction_status_check" CHECK (((interaction_status)::text = ANY (ARRAY[('Scheduled'::character varying)::text, ('Completed'::character varying)::text, ('Follow-up'::character varying)::text, ('Cancelled'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.counselling_followups (
  "counselling_followup_id" BIGSERIAL NOT NULL,
  "student_counselling_id" bigint NOT NULL,
  "followup_date" date NOT NULL DEFAULT CURRENT_DATE,
  "followup_type" character varying(30) NOT NULL,
  "followup_details" text NOT NULL,
  "action_taken" text,
  "assigned_to_employee_id" bigint,
  "next_followup_date" date,
  "followup_status" character varying(20) NOT NULL DEFAULT 'Pending'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "counselling_followups_followup_status_check" CHECK (((followup_status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('In Progress'::character varying)::text, ('Completed'::character varying)::text, ('Cancelled'::character varying)::text]))),
  CONSTRAINT "counselling_followups_followup_type_check" CHECK (((followup_type)::text = ANY (ARRAY[('Mentor Follow-up'::character varying)::text, ('Reviewer Follow-up'::character varying)::text, ('Parent Contact'::character varying)::text, ('Academic Support'::character varying)::text, ('Attendance Warning'::character varying)::text, ('Other'::character varying)::text]))),
  CONSTRAINT "counselling_followups_check" CHECK (((next_followup_date IS NULL) OR (next_followup_date >= followup_date))),
  CONSTRAINT "counselling_followups_pkey" PRIMARY KEY (counselling_followup_id)
);
CREATE TABLE IF NOT EXISTS mentoring.counselling_reviewer_remarks (
  "counselling_reviewer_remark_id" BIGSERIAL NOT NULL,
  "student_counselling_id" bigint NOT NULL,
  "reviewer_id" bigint NOT NULL,
  "reviewer_level" character varying(20) NOT NULL,
  "review_date" date NOT NULL DEFAULT CURRENT_DATE,
  "reviewer_remarks" text NOT NULL,
  "recommendation" text,
  "follow_up_required" boolean NOT NULL DEFAULT false,
  "next_review_date" date,
  "review_status" character varying(20) NOT NULL DEFAULT 'Draft'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "counselling_reviewer_remarks_pkey" PRIMARY KEY (counselling_reviewer_remark_id),
  CONSTRAINT "counselling_reviewer_remarks_student_counselling_id_reviewe_key" UNIQUE (student_counselling_id, reviewer_level),
  CONSTRAINT "counselling_reviewer_remarks_check" CHECK (((next_review_date IS NULL) OR (next_review_date >= review_date))),
  CONSTRAINT "counselling_reviewer_remarks_review_status_check" CHECK (((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text, ('Closed'::character varying)::text]))),
  CONSTRAINT "counselling_reviewer_remarks_reviewer_level_check" CHECK (((reviewer_level)::text = ANY (ARRAY[('Reviewer 1'::character varying)::text, ('Reviewer 2'::character varying)::text, ('Chief Reviewer'::character varying)::text])))
);
CREATE TABLE IF NOT EXISTS mentoring.first_reviewer_remarks (
  "first_reviewer_remark_id" BIGSERIAL NOT NULL,
  "academic_year_id" bigint NOT NULL,
  "student_id" bigint NOT NULL,
  "mentor_id" bigint NOT NULL,
  "reviewer_id" bigint NOT NULL,
  "mentor_reviewer_allotment_id" bigint,
  "review_date" date NOT NULL DEFAULT CURRENT_DATE,
  "information_entered" text,
  "first_reviewer_remarks" text NOT NULL,
  "grading_to_mentor" character varying(30),
  "suggestion_to_mentor" text,
  "follow_up_required" boolean NOT NULL DEFAULT false,
  "next_review_date" date,
  "review_status" character varying(20) NOT NULL DEFAULT 'Draft'::character varying,
  "created_by" bigint,
  "created_at" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_by" bigint,
  "updated_at" timestamp with time zone,
  CONSTRAINT "first_reviewer_remarks_pkey" PRIMARY KEY (first_reviewer_remark_id),
  CONSTRAINT "first_reviewer_remarks_check" CHECK (((next_review_date IS NULL) OR (next_review_date >= review_date))),
  CONSTRAINT "first_reviewer_remarks_grading_to_mentor_check" CHECK (((grading_to_mentor IS NULL) OR ((grading_to_mentor)::text = ANY (ARRAY[('Excellent'::character varying)::text, ('Very Good'::character varying)::text, ('Good'::character varying)::text, ('Average'::character varying)::text, ('Needs Improvement'::character varying)::text, ('Unsatisfactory'::character varying)::text])))),
  CONSTRAINT "first_reviewer_remarks_review_status_check" CHECK (((review_status)::text = ANY (ARRAY[('Draft'::character varying)::text, ('Submitted'::character varying)::text, ('Forwarded'::character varying)::text, ('Closed'::character varying)::text])))
);
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility'::regclass AND conname='employee_mentor_eligibility_created_by_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility ADD CONSTRAINT "employee_mentor_eligibility_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility'::regclass AND conname='employee_mentor_eligibility_employee_id_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility ADD CONSTRAINT "employee_mentor_eligibility_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility'::regclass AND conname='employee_mentor_eligibility_updated_by_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility ADD CONSTRAINT "employee_mentor_eligibility_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.employee_mentor_eligibility') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility_history'::regclass AND conname='employee_mentor_eligibility_h_employee_mentor_eligibility__fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility_history ADD CONSTRAINT "employee_mentor_eligibility_h_employee_mentor_eligibility__fkey" FOREIGN KEY (employee_mentor_eligibility_id) REFERENCES mentoring.employee_mentor_eligibility(employee_mentor_eligibility_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.employee_mentor_eligibility_history'::regclass AND conname='employee_mentor_eligibility_history_changed_by_fkey') THEN ALTER TABLE mentoring.employee_mentor_eligibility_history ADD CONSTRAINT "employee_mentor_eligibility_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.employee_mentor_eligibility') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='fk_mentor_employee_eligibility') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "fk_mentor_employee_eligibility" FOREIGN KEY (employee_mentor_eligibility_id) REFERENCES mentoring.employee_mentor_eligibility(employee_mentor_eligibility_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_created_by_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('departments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_department_id_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_department_id_fkey" FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_employee_id_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentors'::regclass AND conname='mentors_updated_by_fkey') THEN ALTER TABLE mentoring.mentors ADD CONSTRAINT "mentors_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.reviewers'::regclass AND conname='reviewers_employee_id_fkey') THEN ALTER TABLE mentoring.reviewers ADD CONSTRAINT "reviewers_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_academic_year_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_created_by_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_mentor_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('admission_batches') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_programme_batch_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_programme_batch_id_fkey" FOREIGN KEY (programme_batch_id) REFERENCES admission_batches(batch_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('programmes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_programme_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_programme_id_fkey" FOREIGN KEY (programme_id) REFERENCES programmes(programme_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('sections') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_programme_section_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_programme_section_id_fkey" FOREIGN KEY (programme_section_id) REFERENCES sections(section_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('semesters') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_semester_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_semester_id_fkey" FOREIGN KEY (semester_id) REFERENCES semesters(semester_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_student_id_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_mentor_allotments'::regclass AND conname='student_mentor_allotments_updated_by_fkey') THEN ALTER TABLE mentoring.student_mentor_allotments ADD CONSTRAINT "student_mentor_allotments_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_academic_year_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_created_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('departments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_department_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_department_id_fkey" FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_mentor_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotments'::regclass AND conname='mentor_reviewer_allotments_updated_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotments ADD CONSTRAINT "mentor_reviewer_allotments_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentor_reviewer_allotments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotment_details'::regclass AND conname='mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotment_details ADD CONSTRAINT "mentor_reviewer_allotment_det_mentor_reviewer_allotment_id_fkey" FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotment_details'::regclass AND conname='mentor_reviewer_allotment_details_created_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotment_details ADD CONSTRAINT "mentor_reviewer_allotment_details_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_allotment_details'::regclass AND conname='mentor_reviewer_allotment_details_reviewer_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_allotment_details ADD CONSTRAINT "mentor_reviewer_allotment_details_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentor_reviewer_allotments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_histor_mentor_reviewer_allotment_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_histor_mentor_reviewer_allotment_id_fkey" FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_history_changed_by_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_history_new_reviewer_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_history_new_reviewer_id_fkey" FOREIGN KEY (new_reviewer_id) REFERENCES employees(employee_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.mentor_reviewer_change_history'::regclass AND conname='mentor_reviewer_change_history_old_reviewer_id_fkey') THEN ALTER TABLE mentoring.mentor_reviewer_change_history ADD CONSTRAINT "mentor_reviewer_change_history_old_reviewer_id_fkey" FOREIGN KEY (old_reviewer_id) REFERENCES employees(employee_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_academic_year_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.communication_modes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_communication_mode_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_communication_mode_id_fkey" FOREIGN KEY (communication_mode_id) REFERENCES mentoring.communication_modes(communication_mode_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.counselling_purposes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_counselling_purpose_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_counselling_purpose_id_fkey" FOREIGN KEY (counselling_purpose_id) REFERENCES mentoring.counselling_purposes(counselling_purpose_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_created_by_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_mentor_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('admission_batches') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_programme_batch_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_programme_batch_id_fkey" FOREIGN KEY (programme_batch_id) REFERENCES admission_batches(batch_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('programmes') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_programme_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_programme_id_fkey" FOREIGN KEY (programme_id) REFERENCES programmes(programme_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('sections') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_programme_section_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_programme_section_id_fkey" FOREIGN KEY (programme_section_id) REFERENCES sections(section_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('semesters') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_semester_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_semester_id_fkey" FOREIGN KEY (semester_id) REFERENCES semesters(semester_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_student_id_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.student_counsellings'::regclass AND conname='student_counsellings_updated_by_fkey') THEN ALTER TABLE mentoring.student_counsellings ADD CONSTRAINT "student_counsellings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_created_by_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_mentor_id_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.student_counsellings') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_student_counselling_id_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_student_counselling_id_fkey" FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_student_id_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.parent_interactions'::regclass AND conname='parent_interactions_updated_by_fkey') THEN ALTER TABLE mentoring.parent_interactions ADD CONSTRAINT "parent_interactions_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_followups'::regclass AND conname='counselling_followups_assigned_to_employee_id_fkey') THEN ALTER TABLE mentoring.counselling_followups ADD CONSTRAINT "counselling_followups_assigned_to_employee_id_fkey" FOREIGN KEY (assigned_to_employee_id) REFERENCES employees(employee_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_followups'::regclass AND conname='counselling_followups_created_by_fkey') THEN ALTER TABLE mentoring.counselling_followups ADD CONSTRAINT "counselling_followups_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.student_counsellings') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_followups'::regclass AND conname='counselling_followups_student_counselling_id_fkey') THEN ALTER TABLE mentoring.counselling_followups ADD CONSTRAINT "counselling_followups_student_counselling_id_fkey" FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_created_by_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_reviewer_id_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.student_counsellings') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_student_counselling_id_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_student_counselling_id_fkey" FOREIGN KEY (student_counselling_id) REFERENCES mentoring.student_counsellings(student_counselling_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.counselling_reviewer_remarks'::regclass AND conname='counselling_reviewer_remarks_updated_by_fkey') THEN ALTER TABLE mentoring.counselling_reviewer_remarks ADD CONSTRAINT "counselling_reviewer_remarks_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('academic_years') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_academic_year_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(academic_year_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_created_by_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentors') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_mentor_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_mentor_id_fkey" FOREIGN KEY (mentor_id) REFERENCES mentoring.mentors(mentor_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('mentoring.mentor_reviewer_allotments') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_mentor_reviewer_allotment_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_mentor_reviewer_allotment_id_fkey" FOREIGN KEY (mentor_reviewer_allotment_id) REFERENCES mentoring.mentor_reviewer_allotments(mentor_reviewer_allotment_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('employees') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_reviewer_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id) ON DELETE RESTRICT; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('students') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_student_id_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE; END IF; END $mentoring_schema$;
DO $mentoring_schema$ BEGIN IF to_regclass('users') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='mentoring.first_reviewer_remarks'::regclass AND conname='first_reviewer_remarks_updated_by_fkey') THEN ALTER TABLE mentoring.first_reviewer_remarks ADD CONSTRAINT "first_reviewer_remarks_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(user_id) ON DELETE SET NULL; END IF; END $mentoring_schema$;

CREATE TABLE IF NOT EXISTS mentoring.mentor_assignment_changes (
  assignment_change_id BIGSERIAL PRIMARY KEY,
  student_id BIGINT NOT NULL REFERENCES public.students(student_id) ON DELETE CASCADE,
  academic_year_id BIGINT NOT NULL REFERENCES public.academic_years(academic_year_id),
  previous_mentor_id BIGINT REFERENCES mentoring.mentors(mentor_id),
  mentor_id BIGINT NOT NULL REFERENCES mentoring.mentors(mentor_id),
  changed_by BIGINT REFERENCES public.users(user_id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mentor_assignment_changes_student ON mentoring.mentor_assignment_changes(student_id,changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_mentor_activity_student_date ON mentoring.student_counsellings(student_id,discussion_date);
CREATE INDEX IF NOT EXISTS idx_mentor_parent_activity_student_date ON mentoring.parent_interactions(student_id,interaction_date);

-- Hide replaced submenu entries while preserving their permission history.
UPDATE permission_management.system_menus SET status=FALSE WHERE menu_code IN ('MENTORING_MENU_1ST_REVIEWER_REMARKS','MENTORING_MENU_FIRST_REVIEWER_REMARKS','MENTORING_MENU_MENTOR_ACTIVITY','MENTOR_ALLOTMENT_MENU_EXISTING_STUDENT','MENTOR_ALLOTMENT_MENU_PROSPECTIVE_STUDENT','MENTOR_ALLOTMENT_MENU_MENTOR_ALLOTMENT_REPORT');
UPDATE permission_management.system_menus SET display_order=CASE menu_code WHEN 'MENTORING_MENU_REVIEWER_ALLOTMENT' THEN 1 WHEN 'MENTORING_MENU_ALL_COUNSELLING_AND_REVIEWS' THEN 2 WHEN 'MENTOR_ACTIVITY' THEN 3 ELSE display_order END WHERE menu_code IN ('MENTORING_MENU_REVIEWER_ALLOTMENT','MENTORING_MENU_ALL_COUNSELLING_AND_REVIEWS','MENTOR_ACTIVITY');
COMMIT;

ABDC_SOURCE_END server/mentoring-redesign.sql */

/* ABDC_SOURCE_BEGIN server/section-assignment.sql SHA256 1b1cc1c1b54b180b4cd28a2d44a63ebe0ed9b7d7d0c289a40a2d7f2d6e2af151
BEGIN;
-- Batch-level section assignment displayed in Course > Assign Section.
-- Academic sections remain semester-specific for attendance and teacher allocation.
CREATE TABLE IF NOT EXISTS public.batch_section_assignments (
  assignment_id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id) ON DELETE CASCADE,
  section_master_id BIGINT NOT NULL REFERENCES public.section_masters(section_master_id),
  initial_section_id BIGINT REFERENCES public.sections(section_id) ON DELETE SET NULL,
  intake INTEGER NOT NULL CHECK(intake>0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE(batch_id,section_master_id)
);
-- Preserve existing assignments; represent each batch/master once in the table.
INSERT INTO public.batch_section_assignments(batch_id,section_master_id,initial_section_id,intake,is_active)
SELECT DISTINCT ON(s.batch_id,s.section_master_id) s.batch_id,s.section_master_id,s.section_id,GREATEST(COALESCE(s.strength_limit,1),1),s.is_active
FROM public.sections s JOIN public.semesters se ON se.semester_id=s.semester_id
WHERE s.section_master_id IS NOT NULL
ORDER BY s.batch_id,s.section_master_id,se.semester_number,s.section_id
ON CONFLICT(batch_id,section_master_id) DO NOTHING;
COMMIT;

ABDC_SOURCE_END server/section-assignment.sql */

/* ABDC_SOURCE_BEGIN server/section-definitions.sql SHA256 c0f1795fd5267bd85067acdc888a4b52437c8eef46b8e0b2815b1cb3ab03cd43
BEGIN;
-- Section definitions configured by Course > Add Section.
-- Kept separate from semester-specific academic sections and batch assignments.
CREATE TABLE IF NOT EXISTS public.section_definitions (
  section_definition_id BIGSERIAL PRIMARY KEY,
  section_name VARCHAR(100) NOT NULL,
  section_master_id BIGINT NOT NULL REFERENCES public.section_masters(section_master_id),
  admission_course_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  course_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  created_by BIGINT REFERENCES public.users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS section_definitions_mapping_uq
  ON public.section_definitions(LOWER(section_name),section_master_id,admission_course_id,course_id);
CREATE INDEX IF NOT EXISTS section_definitions_course_idx ON public.section_definitions(course_id);
COMMIT;

ABDC_SOURCE_END server/section-definitions.sql */

/* ABDC_SOURCE_BEGIN server/section-masters.sql SHA256 5541588a5df245fb81450a3f87282062794b70a47eebc70f9f4c9a57e9bbb59b
BEGIN;
CREATE TABLE IF NOT EXISTS public.section_masters (
  section_master_id BIGSERIAL PRIMARY KEY,
  section_master_code VARCHAR(30) UNIQUE NOT NULL,
  section_master_name VARCHAR(100) UNIQUE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by BIGINT REFERENCES public.users(user_id),
  updated_at TIMESTAMPTZ,
  updated_by BIGINT REFERENCES public.users(user_id)
);
ALTER TABLE public.section_masters
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES public.users(user_id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_by BIGINT REFERENCES public.users(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS section_masters_name_normalized_uq ON public.section_masters(LOWER(TRIM(section_master_name)));
COMMIT;

ABDC_SOURCE_END server/section-masters.sql */

/* ABDC_SOURCE_BEGIN server/semester-promotion.sql SHA256 11122143ff61d2bc76337db58be16ce2764bce34e1a61d5589fd6d3ba927e570
-- Semester Promotion: Define Semester storage.
BEGIN;
CREATE TABLE IF NOT EXISTS public.programme_semester_definitions (
  programme_semester_id BIGSERIAL PRIMARY KEY,
  course_id BIGINT NOT NULL REFERENCES public.programmes(programme_id),
  programme_batch_id BIGINT NOT NULL REFERENCES public.admission_batches(batch_id),
  semester_id BIGINT NOT NULL REFERENCES public.semesters(semester_id),
  class_type VARCHAR(20) NOT NULL CHECK (class_type IN ('SECTION', 'HOUSE')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  consider_for_accounting BOOLEAN NOT NULL DEFAULT FALSE,
  created_by BIGINT REFERENCES public.users(user_id),
  updated_by BIGINT REFERENCES public.users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ,
  CONSTRAINT uq_programme_semester_definition
    UNIQUE (course_id, programme_batch_id, semester_id, class_type)
);

CREATE INDEX IF NOT EXISTS idx_programme_semester_course
  ON programme_semester_definitions(course_id);

CREATE INDEX IF NOT EXISTS idx_programme_semester_batch
  ON programme_semester_definitions(programme_batch_id);

CREATE INDEX IF NOT EXISTS idx_programme_semester_semester
  ON programme_semester_definitions(semester_id);

-- Semester Promotion / Define Semester uses public.programme_semester_definitions above.
CREATE INDEX IF NOT EXISTS idx_semester_promotion_active_batch ON public.programme_semester_definitions(programme_batch_id,is_active,semester_id);
COMMIT;

ABDC_SOURCE_END server/semester-promotion.sql */

/* ABDC_SOURCE_BEGIN server/student-batch-labels.sql SHA256 aa5dfa4613453f70d2790d225924c1f91e25782a390aadca68f4a4130432cc8a
BEGIN;
-- Correct only the numeric programme-id batch labels generated by older student imports.
-- Preserve custom batch names and all student/batch relationships.
UPDATE public.admission_batches b
SET batch_name=b.admission_year::text||'-'||COALESCE(EXTRACT(YEAR FROM b.expected_end_date)::integer,b.admission_year+CEIL(p.duration_years)::integer)::text
FROM public.programmes p
WHERE p.programme_id=b.programme_id AND b.admission_year>0 AND p.duration_years>0
  AND b.batch_name=b.programme_id::text||'-'||b.admission_year::text;
COMMIT;

ABDC_SOURCE_END server/student-batch-labels.sql */

/* ABDC_SOURCE_BEGIN server/student-section-sync.sql SHA256 32e7a1d34903600c049de8b4aedf9d1eda969c71882a92ae1c4ea67c8ae46261
BEGIN;
WITH eligible AS (
  SELECT st.student_id,MIN(s.section_id) AS section_id,MIN(s.semester_id) AS semester_id
  FROM students st
  JOIN batch_section_assignments a ON a.batch_id=st.batch_id AND a.is_active=TRUE
  JOIN sections s ON s.section_id=a.initial_section_id AND s.batch_id=st.batch_id AND s.is_active=TRUE
  JOIN semesters se ON se.semester_id=s.semester_id AND se.programme_id=st.programme_id
  WHERE st.section_id IS NULL AND COALESCE(st.is_deleted,FALSE)=FALSE
    AND (st.semester_id IS NULL OR st.semester_id=s.semester_id)
  GROUP BY st.student_id HAVING COUNT(DISTINCT s.section_id)=1
)
UPDATE students st SET section_id=e.section_id,semester_id=COALESCE(st.semester_id,e.semester_id),
  student_profile_details=st.student_profile_details||jsonb_build_object('sectionId',e.section_id::text,'semesterId',e.semester_id::text),updated_at=NOW()
FROM eligible e WHERE st.student_id=e.student_id;
COMMIT;

ABDC_SOURCE_END server/student-section-sync.sql */

/* ABDC_SOURCE_BEGIN server/subject_masters.sql SHA256 af14bfb2f858529047010c947b696f5d477b9d1248d5c5a4e1f9fca95b4de194
BEGIN;
-- Academic subject master used by Subjects > Add Subject.
CREATE TABLE IF NOT EXISTS public.subject_masters (
  subject_master_id BIGSERIAL PRIMARY KEY,
  subject_code VARCHAR(30) NOT NULL,
  subject_name VARCHAR(200) NOT NULL,
  subject_short_name VARCHAR(50),
  subject_type VARCHAR(30) NOT NULL DEFAULT 'Theory',
  subject_category VARCHAR(80) NOT NULL,
  department_id BIGINT NOT NULL REFERENCES public.departments(department_id),
  credit NUMERIC(5,2) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by BIGINT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by BIGINT,
  updated_at TIMESTAMP
);
-- Extend older minimal tables without changing existing subjects.
ALTER TABLE public.subject_masters
  ADD COLUMN IF NOT EXISTS subject_short_name VARCHAR(50),
  ADD COLUMN IF NOT EXISTS subject_type VARCHAR(30) NOT NULL DEFAULT 'Theory',
  ADD COLUMN IF NOT EXISTS subject_category VARCHAR(80) NOT NULL DEFAULT 'Professional Core',
  ADD COLUMN IF NOT EXISTS department_id BIGINT REFERENCES public.departments(department_id),
  ADD COLUMN IF NOT EXISTS credit NUMERIC(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_by BIGINT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by BIGINT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;
-- Legacy rows may have no department; assign their correct department before use.
CREATE INDEX IF NOT EXISTS subject_masters_department_idx ON public.subject_masters(department_id);

-- Programme/semester subjects retain their existing primary keys and downstream references.
ALTER TABLE public.subject_masters
  ADD COLUMN IF NOT EXISTS programme_id BIGINT REFERENCES public.programmes(programme_id),
  ADD COLUMN IF NOT EXISTS semester_id BIGINT REFERENCES public.semesters(semester_id);
ALTER TABLE public.subject_masters ALTER COLUMN department_id DROP NOT NULL;
-- Replace only the old single-column code constraint; existing subject data is preserved.
DO $subjects$ DECLARE item RECORD; BEGIN
  FOR item IN SELECT conname FROM pg_constraint WHERE conrelid='public.subject_masters'::regclass
    AND contype='u' AND conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='public.subject_masters'::regclass AND attname='subject_code')]::smallint[]
  LOOP EXECUTE format('ALTER TABLE public.subject_masters DROP CONSTRAINT %I',item.conname); END LOOP;
END $subjects$;
CREATE UNIQUE INDEX IF NOT EXISTS subject_masters_legacy_code_uq ON public.subject_masters(subject_code)
  WHERE programme_id IS NULL AND semester_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS subject_masters_programme_semester_code_uq ON public.subject_masters(programme_id,semester_id,UPPER(subject_code))
  WHERE programme_id IS NOT NULL AND semester_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS semesters_id_programme_uq ON public.semesters(semester_id,programme_id);
DO $subjects$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.subject_masters'::regclass AND conname='subject_masters_scope_check') THEN
    ALTER TABLE public.subject_masters ADD CONSTRAINT subject_masters_scope_check CHECK ((programme_id IS NULL)=(semester_id IS NULL)) NOT VALID;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.subject_masters'::regclass AND conname='subject_masters_semester_programme_fk') THEN
    ALTER TABLE public.subject_masters ADD CONSTRAINT subject_masters_semester_programme_fk FOREIGN KEY(semester_id,programme_id) REFERENCES public.semesters(semester_id,programme_id) NOT VALID;
  END IF;
END $subjects$;
CREATE TABLE IF NOT EXISTS public.subject_components (
  subject_component_id BIGSERIAL PRIMARY KEY,
  subject_master_id BIGINT NOT NULL REFERENCES public.subject_masters(subject_master_id) ON DELETE CASCADE,
  subject_type VARCHAR(20) NOT NULL CHECK(subject_type IN ('THEORY','PRACTICAL')),
  credit NUMERIC(5,2) NOT NULL CHECK(credit>=0),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP,
  UNIQUE(subject_master_id,subject_type)
);
-- Legacy type/credit columns remain available for existing module queries.
-- Existing subjects are not assigned a guessed programme, semester or component.

-- One row per component: Theory and Practical share the subject code and name.
-- Adding a missing component reuses the same subject_master_id.
-- An existing THEORY row and a new PRACTICAL row share one master; credits stay separate.
-- Component uniqueness is (subject_master_id, subject_type), never subject_code alone.
CREATE OR REPLACE VIEW public.subject_component_list AS
SELECT sm.subject_master_id,sc.subject_component_id,sm.programme_id,sm.semester_id,
  p.programme_code,s.semester_name,sm.subject_code,sm.subject_name,
  sc.subject_type,sc.credit,sm.is_active
FROM public.subject_masters sm
JOIN public.subject_components sc ON sc.subject_master_id=sm.subject_master_id
JOIN public.programmes p ON p.programme_id=sm.programme_id
JOIN public.semesters s ON s.semester_id=sm.semester_id;
COMMIT;

ABDC_SOURCE_END server/subject_masters.sql */

/* ABDC_SOURCE_BEGIN src/abit_ims_academics_module.sql SHA256 b4fe8b36797c907585a51f662cbe0ad1fc5d8d53700317baf09f9146d0936038
-- ABIT IMS - ACADEMICS MODULE (PostgreSQL)
-- Assumes existing master tables: users, students, employees, academic_years,
-- programme_batches, semesters, programme_sections, section_groups, subjects,
-- departments and campus_rooms.

BEGIN;
CREATE SCHEMA IF NOT EXISTS academics;

CREATE TABLE IF NOT EXISTS academics.academic_periods (
 academic_period_id BIGSERIAL PRIMARY KEY,
 period_name VARCHAR(50) NOT NULL,
 period_order INT NOT NULL CHECK(period_order>0),
 start_time TIME NOT NULL,
 end_time TIME NOT NULL,
 is_break BOOLEAN NOT NULL DEFAULT FALSE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 UNIQUE(period_order), CHECK(end_time>start_time)
);

CREATE TABLE IF NOT EXISTS academics.attendance_sessions (
 attendance_session_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES programme_batches(programme_batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES programme_sections(programme_section_id),
 section_group_id BIGINT REFERENCES section_groups(section_group_id) ON DELETE SET NULL,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id),
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 academic_period_id BIGINT REFERENCES academics.academic_periods(academic_period_id),
 attendance_date DATE NOT NULL,
 class_mode VARCHAR(20) NOT NULL DEFAULT 'Offline' CHECK(class_mode IN('Offline','Online')),
 topic_covered TEXT,
 session_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(session_status IN('Draft','Submitted','Locked','Cancelled')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 UNIQUE(programme_section_id,section_group_id,subject_id,attendance_date,academic_period_id)
);

CREATE TABLE IF NOT EXISTS academics.student_attendance (
 student_attendance_id BIGSERIAL PRIMARY KEY,
 attendance_session_id BIGINT NOT NULL REFERENCES academics.attendance_sessions(attendance_session_id) ON DELETE CASCADE,
 student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
 attendance_status VARCHAR(15) NOT NULL DEFAULT 'Present' CHECK(attendance_status IN('Present','Absent','Late','Leave','On Duty')),
 remarks TEXT,
 marked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 marked_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 UNIQUE(attendance_session_id,student_id)
);

CREATE TABLE IF NOT EXISTS academics.attendance_corrections (
 attendance_correction_id BIGSERIAL PRIMARY KEY,
 student_attendance_id BIGINT NOT NULL REFERENCES academics.student_attendance(student_attendance_id) ON DELETE CASCADE,
 old_status VARCHAR(15) NOT NULL,
 new_status VARCHAR(15) NOT NULL,
 correction_reason TEXT NOT NULL,
 correction_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(correction_status IN('Pending','Approved','Rejected')),
 requested_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 approved_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 decided_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS academics.examination_types (
 examination_type_id BIGSERIAL PRIMARY KEY,
 examination_type_code VARCHAR(30) NOT NULL UNIQUE,
 examination_type_name VARCHAR(100) NOT NULL UNIQUE,
 exam_scope VARCHAR(20) NOT NULL DEFAULT 'Internal' CHECK(exam_scope IN('Internal','External','University','Practical')),
 is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS academics.examinations (
 examination_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES programme_batches(programme_batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 examination_type_id BIGINT NOT NULL REFERENCES academics.examination_types(examination_type_id),
 examination_name VARCHAR(150) NOT NULL,
 start_date DATE,
 end_date DATE,
 result_status VARCHAR(20) NOT NULL DEFAULT 'Not Published' CHECK(result_status IN('Not Published','Published','Withheld')),
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 CHECK(end_date IS NULL OR start_date IS NULL OR end_date>=start_date)
);

CREATE TABLE IF NOT EXISTS academics.examination_subjects (
 examination_subject_id BIGSERIAL PRIMARY KEY,
 examination_id BIGINT NOT NULL REFERENCES academics.examinations(examination_id) ON DELETE CASCADE,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id),
 exam_date DATE,
 maximum_marks NUMERIC(7,2) NOT NULL CHECK(maximum_marks>0),
 pass_marks NUMERIC(7,2) NOT NULL CHECK(pass_marks>=0 AND pass_marks<=maximum_marks),
 marks_entry_deadline TIMESTAMPTZ,
 marks_lock_status VARCHAR(20) NOT NULL DEFAULT 'Open' CHECK(marks_lock_status IN('Open','Closed','Locked')),
 UNIQUE(examination_id,subject_id)
);

CREATE TABLE IF NOT EXISTS academics.student_marks (
 student_mark_id BIGSERIAL PRIMARY KEY,
 examination_subject_id BIGINT NOT NULL REFERENCES academics.examination_subjects(examination_subject_id) ON DELETE CASCADE,
 student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
 marks_obtained NUMERIC(7,2),
 attendance_status VARCHAR(15) NOT NULL DEFAULT 'Present' CHECK(attendance_status IN('Present','Absent','Malpractice','Withheld')),
 result_status VARCHAR(15) CHECK(result_status IN('Pass','Fail','Absent','Withheld')),
 remarks TEXT,
 entered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 entered_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 UNIQUE(examination_subject_id,student_id)
);

CREATE TABLE IF NOT EXISTS academics.university_marks_imports (
 university_marks_import_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES programme_batches(programme_batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 source_file_name VARCHAR(255),
 import_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(import_status IN('Pending','Processing','Completed','Failed')),
 total_rows INT NOT NULL DEFAULT 0,
 successful_rows INT NOT NULL DEFAULT 0,
 failed_rows INT NOT NULL DEFAULT 0,
 error_log TEXT,
 imported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 imported_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS academics.student_backpapers (
 student_backpaper_id BIGSERIAL PRIMARY KEY,
 student_id BIGINT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 attempt_number INT NOT NULL DEFAULT 1 CHECK(attempt_number>0),
 registration_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(registration_status IN('Pending','Registered','Appeared','Cleared','Failed','Cancelled')),
 examination_id BIGINT REFERENCES academics.examinations(examination_id) ON DELETE SET NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(student_id,subject_id,attempt_number)
);

CREATE TABLE IF NOT EXISTS academics.lesson_plans (
 lesson_plan_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES programme_batches(programme_batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES programme_sections(programme_section_id),
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id),
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 plan_title VARCHAR(200) NOT NULL,
 planned_start_date DATE,
 planned_end_date DATE,
 total_planned_periods INT NOT NULL DEFAULT 0 CHECK(total_planned_periods>=0),
 plan_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(plan_status IN('Draft','Submitted','Approved','Rejected','Completed')),
 approved_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 approved_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 CHECK(planned_end_date IS NULL OR planned_start_date IS NULL OR planned_end_date>=planned_start_date)
);

CREATE TABLE IF NOT EXISTS academics.lesson_plan_units (
 lesson_plan_unit_id BIGSERIAL PRIMARY KEY,
 lesson_plan_id BIGINT NOT NULL REFERENCES academics.lesson_plans(lesson_plan_id) ON DELETE CASCADE,
 unit_number INT NOT NULL CHECK(unit_number>0),
 unit_title VARCHAR(200) NOT NULL,
 topics TEXT NOT NULL,
 planned_periods INT NOT NULL DEFAULT 0,
 completed_periods INT NOT NULL DEFAULT 0,
 planned_date DATE,
 completion_date DATE,
 completion_status VARCHAR(20) NOT NULL DEFAULT 'Not Started' CHECK(completion_status IN('Not Started','In Progress','Completed','Deferred')),
 UNIQUE(lesson_plan_id,unit_number)
);

CREATE TABLE IF NOT EXISTS academics.course_outcomes (
 course_outcome_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
 co_code VARCHAR(20) NOT NULL,
 co_statement TEXT NOT NULL,
 bloom_level VARCHAR(10),
 target_percentage NUMERIC(5,2) CHECK(target_percentage BETWEEN 0 AND 100),
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 UNIQUE(subject_id,co_code)
);

CREATE TABLE IF NOT EXISTS academics.lesson_plan_co_mapping (
 lesson_plan_unit_id BIGINT NOT NULL REFERENCES academics.lesson_plan_units(lesson_plan_unit_id) ON DELETE CASCADE,
 course_outcome_id BIGINT NOT NULL REFERENCES academics.course_outcomes(course_outcome_id) ON DELETE CASCADE,
 PRIMARY KEY(lesson_plan_unit_id,course_outcome_id)
);

CREATE TABLE IF NOT EXISTS academics.preferred_books (
 preferred_book_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
 book_title VARCHAR(255) NOT NULL,
 author_name VARCHAR(200),
 publisher_name VARCHAR(200),
 edition VARCHAR(50),
 isbn VARCHAR(30),
 preference_type VARCHAR(20) NOT NULL DEFAULT 'Text Book' CHECK(preference_type IN('Text Book','Reference Book','Supplementary')),
 display_order INT NOT NULL DEFAULT 1,
 is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS academics.lecture_notes (
 lecture_note_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 title VARCHAR(255) NOT NULL,
 unit_number INT,
 file_name VARCHAR(255),
 file_path TEXT,
 note_url TEXT,
 description TEXT,
 publish_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(publish_status IN('Draft','Published','Archived')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS academics.video_lectures (
 video_lecture_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 title VARCHAR(255) NOT NULL,
 unit_number INT,
 video_url TEXT NOT NULL,
 duration_minutes INT CHECK(duration_minutes IS NULL OR duration_minutes>=0),
 description TEXT,
 publish_status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(publish_status IN('Draft','Published','Archived')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS academics.ppt_presentations (
 ppt_presentation_id BIGSERIAL PRIMARY KEY,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
 faculty_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 title VARCHAR(255) NOT NULL,
 unit_number INT,
 file_name VARCHAR(255),
 file_path TEXT,
 presentation_status VARCHAR(20) NOT NULL DEFAULT 'Submitted' CHECK(presentation_status IN('Draft','Submitted','Under Review','Approved','Revision Required','Rejected')),
 submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS academics.ppt_reviewers (
 ppt_reviewer_id BIGSERIAL PRIMARY KEY,
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id) ON DELETE CASCADE,
 department_id BIGINT REFERENCES departments(department_id) ON DELETE SET NULL,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 UNIQUE(employee_id,department_id)
);

CREATE TABLE IF NOT EXISTS academics.ppt_reviews (
 ppt_review_id BIGSERIAL PRIMARY KEY,
 ppt_presentation_id BIGINT NOT NULL REFERENCES academics.ppt_presentations(ppt_presentation_id) ON DELETE CASCADE,
 reviewer_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 review_status VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK(review_status IN('Pending','Approved','Revision Required','Rejected')),
 score NUMERIC(5,2) CHECK(score IS NULL OR score BETWEEN 0 AND 100),
 comments TEXT,
 reviewed_at TIMESTAMPTZ,
 UNIQUE(ppt_presentation_id,reviewer_employee_id)
);

CREATE TABLE IF NOT EXISTS academics.subject_teacher_allocations (
 subject_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES programme_batches(programme_batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES programme_sections(programme_section_id),
 section_group_id BIGINT REFERENCES section_groups(section_group_id) ON DELETE SET NULL,
 subject_id BIGINT NOT NULL REFERENCES subjects(subject_id),
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 allocation_role VARCHAR(20) NOT NULL DEFAULT 'Primary' CHECK(allocation_role IN('Primary','Co-Teacher','Practical','Tutorial')),
 workload_hours NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK(workload_hours>=0),
 effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
 effective_to DATE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 created_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
 CHECK(effective_to IS NULL OR effective_to>=effective_from)
);

CREATE TABLE IF NOT EXISTS academics.class_teacher_allocations (
 class_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_section_id BIGINT NOT NULL REFERENCES programme_sections(programme_section_id),
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
 effective_to DATE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(effective_to IS NULL OR effective_to>=effective_from)
);

CREATE TABLE IF NOT EXISTS academics.substitute_teacher_allocations (
 substitute_teacher_allocation_id BIGSERIAL PRIMARY KEY,
 subject_teacher_allocation_id BIGINT NOT NULL REFERENCES academics.subject_teacher_allocations(subject_teacher_allocation_id),
 original_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 substitute_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 substitution_date DATE NOT NULL,
 academic_period_id BIGINT REFERENCES academics.academic_periods(academic_period_id),
 reason TEXT,
 status VARCHAR(20) NOT NULL DEFAULT 'Assigned' CHECK(status IN('Assigned','Completed','Cancelled','Restored')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(original_employee_id<>substitute_employee_id)
);

CREATE TABLE IF NOT EXISTS academics.teacher_allocation_history (
 teacher_allocation_history_id BIGSERIAL PRIMARY KEY,
 allocation_type VARCHAR(30) NOT NULL CHECK(allocation_type IN('Subject Teacher','Class Teacher','Substitute Teacher')),
 allocation_record_id BIGINT NOT NULL,
 action_type VARCHAR(20) NOT NULL CHECK(action_type IN('Created','Updated','Deactivated','Restored')),
 old_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE SET NULL,
 new_employee_id BIGINT REFERENCES employees(employee_id) ON DELETE SET NULL,
 reason TEXT,
 action_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 action_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS academics.timetable_headers (
 timetable_id BIGSERIAL PRIMARY KEY,
 academic_year_id BIGINT NOT NULL REFERENCES academic_years(academic_year_id),
 programme_batch_id BIGINT NOT NULL REFERENCES programme_batches(programme_batch_id),
 semester_id BIGINT NOT NULL REFERENCES semesters(semester_id),
 programme_section_id BIGINT NOT NULL REFERENCES programme_sections(programme_section_id),
 timetable_name VARCHAR(150) NOT NULL,
 timetable_type VARCHAR(20) NOT NULL DEFAULT 'Offline' CHECK(timetable_type IN('Offline','Online','Hybrid')),
 effective_from DATE NOT NULL,
 effective_to DATE,
 status VARCHAR(20) NOT NULL DEFAULT 'Draft' CHECK(status IN('Draft','Published','Archived')),
 published_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(effective_to IS NULL OR effective_to>=effective_from)
);

CREATE TABLE IF NOT EXISTS academics.timetable_entries (
 timetable_entry_id BIGSERIAL PRIMARY KEY,
 timetable_id BIGINT NOT NULL REFERENCES academics.timetable_headers(timetable_id) ON DELETE CASCADE,
 day_of_week SMALLINT NOT NULL CHECK(day_of_week BETWEEN 1 AND 7),
 academic_period_id BIGINT NOT NULL REFERENCES academics.academic_periods(academic_period_id),
 subject_id BIGINT REFERENCES subjects(subject_id) ON DELETE SET NULL,
 employee_id BIGINT REFERENCES employees(employee_id) ON DELETE SET NULL,
 room_id BIGINT REFERENCES campus_rooms(room_id) ON DELETE SET NULL,
 section_group_id BIGINT REFERENCES section_groups(section_group_id) ON DELETE SET NULL,
 online_meeting_url TEXT,
 entry_type VARCHAR(20) NOT NULL DEFAULT 'Class' CHECK(entry_type IN('Class','Laboratory','Tutorial','Break','Activity')),
 remarks TEXT,
 UNIQUE(timetable_id,day_of_week,academic_period_id,section_group_id)
);

CREATE TABLE IF NOT EXISTS academics.timetable_change_log (
 timetable_change_log_id BIGSERIAL PRIMARY KEY,
 timetable_entry_id BIGINT NOT NULL REFERENCES academics.timetable_entries(timetable_entry_id) ON DELETE CASCADE,
 change_type VARCHAR(20) NOT NULL CHECK(change_type IN('Created','Updated','Deleted','Substituted')),
 old_values JSONB,
 new_values JSONB,
 changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 changed_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS academics.report_runs (
 report_run_id BIGSERIAL PRIMARY KEY,
 report_code VARCHAR(80) NOT NULL,
 report_name VARCHAR(150) NOT NULL,
 filter_json JSONB,
 generated_format VARCHAR(10) NOT NULL DEFAULT 'PDF' CHECK(generated_format IN('PDF','XLSX','CSV','HTML')),
 file_path TEXT,
 row_count INT NOT NULL DEFAULT 0,
 generated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 generated_by BIGINT REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE OR REPLACE VIEW academics.vw_student_attendance_summary AS
SELECT sa.student_id, ats.academic_year_id, ats.semester_id, ats.subject_id,
 COUNT(*) total_classes,
 COUNT(*) FILTER(WHERE sa.attendance_status='Present') present_classes,
 COUNT(*) FILTER(WHERE sa.attendance_status='Absent') absent_classes,
 ROUND(100.0*COUNT(*) FILTER(WHERE sa.attendance_status='Present')/NULLIF(COUNT(*),0),2) attendance_percentage
FROM academics.student_attendance sa
JOIN academics.attendance_sessions ats ON ats.attendance_session_id=sa.attendance_session_id
WHERE ats.session_status IN('Submitted','Locked')
GROUP BY sa.student_id,ats.academic_year_id,ats.semester_id,ats.subject_id;

CREATE OR REPLACE VIEW academics.vw_student_marks_summary AS
SELECT sm.student_id,e.academic_year_id,e.programme_batch_id,e.semester_id,
 es.subject_id,e.examination_id,es.maximum_marks,es.pass_marks,
 sm.marks_obtained,sm.attendance_status,sm.result_status
FROM academics.student_marks sm
JOIN academics.examination_subjects es ON es.examination_subject_id=sm.examination_subject_id
JOIN academics.examinations e ON e.examination_id=es.examination_id;

CREATE OR REPLACE VIEW academics.vw_faculty_academic_load AS
SELECT employee_id,academic_year_id,semester_id,
 COUNT(DISTINCT subject_id) subjects_assigned,
 COUNT(DISTINCT programme_section_id) sections_assigned,
 COALESCE(SUM(workload_hours),0) total_workload_hours
FROM academics.subject_teacher_allocations
WHERE is_active=TRUE
GROUP BY employee_id,academic_year_id,semester_id;

CREATE OR REPLACE VIEW academics.vw_course_coverage AS
SELECT lp.lesson_plan_id,lp.subject_id,lp.faculty_employee_id,lp.programme_section_id,
 lp.total_planned_periods,COALESCE(SUM(lpu.completed_periods),0) completed_periods,
 ROUND(100.0*COALESCE(SUM(lpu.completed_periods),0)/NULLIF(lp.total_planned_periods,0),2) coverage_percentage
FROM academics.lesson_plans lp
LEFT JOIN academics.lesson_plan_units lpu ON lpu.lesson_plan_id=lp.lesson_plan_id
GROUP BY lp.lesson_plan_id,lp.subject_id,lp.faculty_employee_id,lp.programme_section_id,lp.total_planned_periods;

CREATE INDEX IF NOT EXISTS idx_attendance_session_date ON academics.attendance_sessions(attendance_date);
CREATE INDEX IF NOT EXISTS idx_student_attendance_student ON academics.student_attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_student_marks_student ON academics.student_marks(student_id);
CREATE INDEX IF NOT EXISTS idx_subject_teacher_employee ON academics.subject_teacher_allocations(employee_id);
CREATE INDEX IF NOT EXISTS idx_timetable_section ON academics.timetable_headers(programme_section_id);

INSERT INTO academics.examination_types(examination_type_code,examination_type_name,exam_scope) VALUES
('IA1','Internal Assessment 1','Internal'),
('IA2','Internal Assessment 2','Internal'),
('SEM','Semester Examination','University'),
('PRAC','Practical Examination','Practical')
ON CONFLICT(examination_type_code) DO NOTHING;

COMMIT;

ABDC_SOURCE_END src/abit_ims_academics_module.sql */
