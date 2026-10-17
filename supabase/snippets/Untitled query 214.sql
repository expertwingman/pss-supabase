select b.*
from (select set_config('request.jwt.claims',
        json_build_object('sub', (select id from auth.users where email='andi@test.local'),
                          'role','authenticated')::text, true)) s,
     lateral book_window((select id from sale_windows where label = 'Hijau · 08–10')) b;