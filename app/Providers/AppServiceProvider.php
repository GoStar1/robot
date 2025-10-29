<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // 只有在配置了 FORCE_HTTPS=true 时才强制使用 HTTPS
        if (env('FORCE_HTTPS', false)) {
            \URL::forceScheme('https');
        }
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        view()->composer('*', 'App\Composers\AdminComposer');
    }
}
