
requires 'perl', '5.34.0';
requires 'Log::Any';
requires 'Module::CPANfile';

on test => sub {
    requires 'Test2::V0';
    requires 'Test2::Mock';
};

on develop => sub {
    requires 'App::FatPacker';
};
