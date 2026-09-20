<?php

declare(strict_types=1);

$panel = getenv('PANEL_DIR') ?: '/var/www/pterodactyl';
chdir($panel);
require $panel . '/vendor/autoload.php';
$app = require $panel . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Hash;
use Pterodactyl\Models\User;
use Symfony\Component\Process\Process;

$action = getenv('HKZ_ADMIN_ACTION') ?: 'ensure';
$email = getenv('HKZ_USER_EMAIL') ?: '';
$username = getenv('HKZ_USER_USERNAME') ?: 'admin';
$first = getenv('HKZ_USER_FIRST') ?: 'Admin';
$last = getenv('HKZ_USER_LAST') ?: 'User';
$raw = getenv('HKZ_USER_PASSWORD_B64') ?: '';
$pass = $raw !== '' ? base64_decode($raw, true) : false;

if ($pass === false || $email === '' || $pass === '') {
    fwrite(STDERR, "missing credentials\n");
    exit(2);
}

$user = User::where('email', $email)->first();
if (!$user) {
    $user = User::where('username', $username)->first();
}

if ($action === 'verify') {
    if (!$user) {
        exit(1);
    }
    exit(Hash::check($pass, $user->password) ? 0 : 1);
}

if ($user) {
    $user->password = Hash::make($pass);
    $user->root_admin = true;
    $user->email = $email;
    $user->username = $username;
    $user->name_first = $first;
    $user->name_last = $last;
    $user->save();
    exit(0);
}

$proc = new Process(
    [
        PHP_BINARY,
        $panel . '/artisan',
        'p:user:make',
        '--email=' . $email,
        '--username=' . $username,
        '--name-first=' . $first,
        '--name-last=' . $last,
        '--password=' . $pass,
        '--admin=1',
        '--no-interaction',
    ],
    $panel
);
$proc->setTimeout(120);
$proc->run();
if (!$proc->isSuccessful()) {
    fwrite(STDERR, $proc->getErrorOutput() . $proc->getOutput());
    exit((int) $proc->getExitCode());
}
exit(0);
