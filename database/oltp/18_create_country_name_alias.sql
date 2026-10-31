CREATE TABLE IF NOT EXISTS ctl.country_name_alias (
    source_system       VARCHAR(30)  NOT NULL,
    source_country_name VARCHAR(100) NOT NULL,
    country_code        CHAR(2)      NOT NULL,
    notes               VARCHAR(250),

    CONSTRAINT pk_country_name_alias
        PRIMARY KEY (source_system, source_country_name),

    CONSTRAINT fk_country_name_alias_country
        FOREIGN KEY (country_code)
        REFERENCES oltp.country(country_code)
);

-- Kosovo: extensión propia del proyecto porque no dispone
-- de código ISO 3166-1 alpha-2 oficial en nuestro catálogo.
INSERT INTO oltp.country
    (country_code, country_code_3, country_name, active_flag)
VALUES
    ('XK', NULL, 'Kosovo', TRUE)
ON CONFLICT (country_code) DO NOTHING;

INSERT INTO ctl.country_name_alias
    (source_system, source_country_name, country_code, notes)
VALUES
    ('IBM_CORE', 'Brunei',                            'BN', 'Alias IBM'),
    ('IBM_CORE', 'Cote d''Ivoire',                    'CI', 'Alias IBM'),
    ('IBM_CORE', 'Czech Republic',                    'CZ', 'Nombre histórico IBM'),
    ('IBM_CORE', 'Democratic Republic of the Congo',  'CD', 'Alias IBM'),
    ('IBM_CORE', 'East Timor (Timor-Leste)',          'TL', 'Alias IBM'),
    ('IBM_CORE', 'Iran',                              'IR', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'Kosovo',                            'XK', 'Código no ISO propio del proyecto'),
    ('IBM_CORE', 'Macedonia',                         'MK', 'Nombre histórico IBM'),
    ('IBM_CORE', 'Micronesia',                        'FM', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'Moldova',                           'MD', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'Myanmar (Burma)',                   'MM', 'Alias IBM'),
    ('IBM_CORE', 'Republic of the Congo',             'CG', 'Alias IBM'),
    ('IBM_CORE', 'Russia',                            'RU', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'South Korea',                       'KR', 'Alias IBM'),
    ('IBM_CORE', 'Swaziland',                         'SZ', 'Nombre histórico IBM'),
    ('IBM_CORE', 'Syria',                             'SY', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'Taiwan',                            'TW', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'Tanzania',                          'TZ', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'The Bahamas',                       'BS', 'Alias IBM'),
    ('IBM_CORE', 'Turkey',                            'TR', 'Nombre IBM'),
    ('IBM_CORE', 'Vatican City',                      'VA', 'Alias IBM'),
    ('IBM_CORE', 'Venezuela',                         'VE', 'Nombre simplificado IBM'),
    ('IBM_CORE', 'Vietnam',                           'VN', 'Nombre simplificado IBM')
ON CONFLICT (source_system, source_country_name)
DO UPDATE SET
    country_code = EXCLUDED.country_code,
    notes        = EXCLUDED.notes;