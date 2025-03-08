
requires 'perl', '5.34.0';
requires 'Log::Any';
requires 'Module::CPANfile';

on develop => sub {
    requires 'App::FatPacker';
};
