import datetime

utc = datetime.timezone.utc
date_from_ordinal = datetime.date.fromordinal
timedelta = datetime.timedelta

pg_epoch_datetime = datetime.datetime(2000, 1, 1)
cdef long pg_epoch_datetime_ts = \
    cpython.PyLong_AsLong(int(pg_epoch_datetime.timestamp()))

pg_epoch_datetime_utc = datetime.datetime(2000, 1, 1, tzinfo=utc)
cdef long pg_epoch_datetime_utc_ts = \
    cpython.PyLong_AsLong(pg_epoch_datetime_utc.timestamp())

pg_epoch_date = datetime.date(2000, 1, 1)
cdef long pg_date_offset_ord = \
    cpython.PyLong_AsLong(pg_epoch_date.toordinal())

# Binary representations of infinity for datetimes.
cdef long long pg_time64_infinity = 0x7fffffffffffffff
cdef long long pg_time64_negative_infinity = 0x8000000000000000
cdef int32_t pg_date_infinity = 0x7fffffff
cdef int32_t pg_date_negative_infinity = 0x80000000

infinity_datetime = datetime.datetime(
    datetime.MAXYEAR, 12, 31, 23, 59, 59, 999999)

cdef long infinity_datetime_ord = cpython.PyLong_AsLong(
    infinity_datetime.toordinal())

cdef int64_t infinity_datetime_ts = 252455615999999999

negative_infinity_datetime = datetime.datetime(
    datetime.MINYEAR, 1, 1, 0, 0, 0, 0)

cdef long negative_infinity_datetime_ord = cpython.PyLong_AsLong(
    negative_infinity_datetime.toordinal())

cdef int64_t negative_infinity_datetime_ts = -63082281600000000

infinity_date = datetime.date(datetime.MAXYEAR, 12, 31)

cdef long infinity_date_ord = cpython.PyLong_AsLong(
    infinity_date.toordinal())

negative_infinity_date = datetime.date(datetime.MINYEAR, 1, 1)

cdef long negative_infinity_date_ord = cpython.PyLong_AsLong(
    negative_infinity_date.toordinal())


cdef inline _encode_time(WriteBuffer buf, int64_t seconds,
                         uint32_t microseconds):
    # XXX: add support for double timestamps
    # int64 timestamps,
    cdef int64_t ts = seconds * 1000000 + microseconds

    if ts == infinity_datetime_ts:
        buf.write_int64(pg_time64_infinity)
    elif ts == negative_infinity_datetime_ts:
        buf.write_int64(pg_time64_negative_infinity)
    else:
        buf.write_int64(ts)


cdef inline int32_t _decode_time(const char *data, int64_t *seconds,
                                 uint32_t *microseconds):
    # XXX: add support for double timestamps
    # int64 timestamps,
    cdef int64_t ts = hton.unpack_int64(data)

    if ts == pg_time64_infinity:
        return 1
    elif ts == pg_time64_negative_infinity:
        return -1

    seconds[0] = <int64_t>(ts / 1000000)
    microseconds[0] = <uint32_t>(ts % 1000000)

    return 0


cdef date_encode(ConnectionSettings settings, WriteBuffer buf, obj):
    cdef:
        int32_t ordinal = cpython.PyLong_AsLongLong(obj.toordinal())
        int32_t pg_ordinal

    if ordinal == infinity_date_ord:
        pg_ordinal = pg_date_infinity
    elif ordinal == negative_infinity_date_ord:
        pg_ordinal = pg_date_negative_infinity
    else:
        pg_ordinal = ordinal - pg_date_offset_ord

    buf.write_int32(4)
    buf.write_int32(pg_ordinal)


cdef date_decode(ConnectionSettings settings, const char* data, int32_t len):
    cdef int32_t pg_ordinal = hton.unpack_int32(data)

    if pg_ordinal == pg_date_infinity:
        return infinity_date
    elif pg_ordinal == pg_date_negative_infinity:
        return negative_infinity_date
    else:
        return date_from_ordinal(pg_ordinal + pg_date_offset_ord)


cdef timestamp_encode(ConnectionSettings settings, WriteBuffer buf, obj):
    delta = obj - pg_epoch_datetime
    cdef:
        int64_t seconds = cpython.PyLong_AsLong(delta.days) * 86400 + \
                                cpython.PyLong_AsLong(delta.seconds)
        int32_t microseconds = cpython.PyLong_AsLong(delta.microseconds)

    buf.write_int32(8)
    _encode_time(buf, seconds, microseconds)


cdef timestamp_decode(ConnectionSettings settings, const char* data,
                      int32_t len):
    cdef:
        int64_t seconds
        uint32_t microseconds
        int32_t inf = _decode_time(data, &seconds, &microseconds)

    if inf > 0:
        # positive infinity
        return infinity_datetime
    elif inf < 0:
        # negative infinity
        return negative_infinity_datetime
    else:
        return pg_epoch_datetime.__add__(
            timedelta(0, seconds, microseconds))


cdef timestamptz_encode(ConnectionSettings settings, WriteBuffer buf, obj):
    buf.write_int32(8)

    if obj == infinity_datetime:
        buf.write_int64(pg_time64_infinity)
        return
    elif obj == negative_infinity_datetime:
        buf.write_int64(pg_time64_negative_infinity)
        return

    delta = obj.astimezone(utc) - pg_epoch_datetime_utc
    cdef:
        int64_t seconds = cpython.PyLong_AsLong(delta.days) * 86400 + \
                                cpython.PyLong_AsLong(delta.seconds)
        int32_t microseconds = cpython.PyLong_AsLong(delta.microseconds)

    _encode_time(buf, seconds, microseconds)


cdef timestamptz_decode(ConnectionSettings settings, const char* data,
                        int32_t len):
    cdef:
        int64_t seconds
        uint32_t microseconds
        int32_t inf = _decode_time(data, &seconds, &microseconds)

    if inf > 0:
        # positive infinity
        return infinity_datetime
    elif inf < 0:
        # negative infinity
        return negative_infinity_datetime
    else:
        return pg_epoch_datetime_utc.__add__(
            timedelta(0, seconds, microseconds))


cdef time_encode(ConnectionSettings settings, WriteBuffer buf, obj):
    cdef:
        int64_t seconds = cpython.PyLong_AsLong(obj.hour) * 3600 + \
                            cpython.PyLong_AsLong(obj.minute) * 60 + \
                            cpython.PyLong_AsLong(obj.second)
        int32_t microseconds = cpython.PyLong_AsLong(obj.microsecond)

    buf.write_int32(8)
    _encode_time(buf, seconds, microseconds)


cdef time_decode(ConnectionSettings settings, const char* data,
                 int32_t len):
    cdef:
        int64_t seconds
        uint32_t microseconds

    _decode_time(data, &seconds, &microseconds)

    cdef:
        int32_t minutes = <int32_t>(seconds / 60)
        int32_t sec = seconds % 60
        int32_t hours = <int32_t>(minutes / 60)
        int32_t min = minutes % 60

    return datetime.time(hours, min, sec, microseconds)


cdef timetz_encode(ConnectionSettings settings, WriteBuffer buf, obj):
    offset = obj.tzinfo.utcoffset(None)

    cdef:
        int32_t offset_sec = cpython.PyLong_AsLong(offset.days) * 24 * 60 * 60 + \
                            cpython.PyLong_AsLong(offset.seconds)
        int64_t seconds = cpython.PyLong_AsLong(obj.hour) * 3600 + \
                            cpython.PyLong_AsLong(obj.minute) * 60 + \
                            cpython.PyLong_AsLong(obj.second)
        int32_t microseconds = cpython.PyLong_AsLong(obj.microsecond)

    buf.write_int32(12)
    _encode_time(buf, seconds, microseconds)
    buf.write_int32(offset_sec)


cdef timetz_decode(ConnectionSettings settings, const char* data,
                   int32_t len):
    time = time_decode(settings, data, len)
    cdef int32_t offset = <int32_t>(hton.unpack_int32(&data[8]) / 60)
    return time.replace(tzinfo=datetime.timezone(timedelta(minutes=offset)))


cdef interval_encode(ConnectionSettings settings, WriteBuffer buf, obj):
    cdef:
        int32_t days = cpython.PyLong_AsLong(obj.days)
        int64_t seconds = cpython.PyLong_AsLongLong(obj.seconds)
        int32_t microseconds = cpython.PyLong_AsLong(obj.microseconds)

    buf.write_int32(16)
    _encode_time(buf, seconds, microseconds)
    buf.write_int32(days)
    buf.write_int32(0) # Months


cdef interval_decode(ConnectionSettings settings, const char* data,
                     int32_t len):
    cdef:
        int32_t days = hton.unpack_int32(&data[8])
        int32_t months = hton.unpack_int32(&data[12])
        int64_t seconds
        uint32_t microseconds

    _decode_time(data, &seconds, &microseconds)

    return datetime.timedelta(days=days + months * 30, seconds=seconds,
                              microseconds=microseconds)


cdef inline void init_datetime_codecs():
    codec_map[DATEOID].encode = date_encode
    codec_map[DATEOID].decode = date_decode
    codec_map[DATEOID].format = PG_FORMAT_BINARY
    codec_map[TIMEOID].encode = time_encode
    codec_map[TIMEOID].decode = time_decode
    codec_map[TIMEOID].format = PG_FORMAT_BINARY
    codec_map[TIMETZOID].encode = timetz_encode
    codec_map[TIMETZOID].decode = timetz_decode
    codec_map[TIMETZOID].format = PG_FORMAT_BINARY
    codec_map[TIMESTAMPOID].encode = timestamp_encode
    codec_map[TIMESTAMPOID].decode = timestamp_decode
    codec_map[TIMESTAMPOID].format = PG_FORMAT_BINARY
    codec_map[TIMESTAMPTZOID].encode = timestamptz_encode
    codec_map[TIMESTAMPTZOID].decode = timestamptz_decode
    codec_map[TIMESTAMPTZOID].format = PG_FORMAT_BINARY
    codec_map[INTERVALOID].encode = interval_encode
    codec_map[INTERVALOID].decode = interval_decode
    codec_map[INTERVALOID].format = PG_FORMAT_BINARY
