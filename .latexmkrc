$no_CP_conversions = 1;

use File::Basename;

# Gera as listas de siglas e glossario antes da recompilacao do PDF.
add_cus_dep('acn', 'acr', 0, 'run_makeglossaries');
add_cus_dep('glo', 'gls', 0, 'run_makeglossaries');

sub run_makeglossaries {
    my ($name, $path) = fileparse($_[0]);
    return system('makeglossaries', '-d', $path, $name);
}
