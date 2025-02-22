# AdGuard Home для Keenetic

AdGuard Home — это удобный и мощный инструмент для управления интернетом в вашей сети на уровне DNS/DHCP.

Для всей сети и каждого устройства отдельно можно:

*   Назначить любое количество DNS-серверов
*   Заблокировать рекламу и трекинг (в пределах возможностей DNS)
*   Включить «безопасный» поиск для детей
*   Ограничить доступ к нежелательным или подозрительным сайтам
*   Блокировать доступ к любым сайтам или приложениям в заданное время (например, к соцсетям перед сном)
*   Просматривать журнал запросов и общую статистику посещений.

Это даёт расширенный контроль над вашей сетью.

## I. Установка

Представленный вариант установки создан на базе этой инструкции - [https://dartraiden.github.io/AdGuard-Home-Keenetic](https://dartraiden.github.io/AdGuard-Home-Keenetic)

1.  Установите поддержку репозитория Entware по инструкции.

2.  Установите AdGuard Home, запустив команды в консоли с Entware:

    ```bash
    opkg update
    opkg install adguardhome-go
    ```

    Дождитесь загрузки и установки.

3.  Отключите DNS-сервер, встроенный в прошивку Keenetic.

    Это нужно чтобы AdGuard Home мог занять 53 порт и обрабатывать DNS-запросы.

    Для этого перейдите по адресу `http://192.168.1.1/a` (или используйте свой актуальный адрес роутера вместо `192.168.1.1`).

    В веб-интерфейсе откроется страница Web cli, с которой можно отправлять команды для роутера:

    ```
    Web cli
    ```

    Введите команду в консоль:

    ```bash
    opkg dns-override
    ```

    Потом эту команду:

    ```bash
    system configuration save
    ```

    Теперь перезагрузите роутер.

4.  Запустите AdGuard Home командой в Entware:

    ```bash
    /opt/etc/init.d/S99adguardhome start
    ```

5.  Откройте в браузере мастер первоначальной настройки AdGuard Home по адресу `http://IP-адрес-роутера:3000`

    Если всё стандартно, то адрес будет такой - `http://192.168.1.1:3000`

6.  Произведите первоначальную настройку:

    *   Веб-интерфейс повесьте на "Все интерфейсы", порт `1234` или любой выше от `1000` до `65535`.
    *   DNS-сервер повесьте на "Все интерфейсы", порт `53`.
    *   Также придумайте логин и пароль (чтобы не усложнять, можно использовать логин/пароль от админки роутера).

7.  Измените адрес DNS в роутере на `IP-адрес-роутера` (в нашем примере это `192.168.1.1`) - это DNS адрес самого AdGuard Home.

    Так же нужно выбрать "Игнорировать DNSv4 DNS интернет-провайдера", если есть, и DNSv6 тоже.

8.  Теперь зайдите по адресу `http://IP-адрес-роутера:1234` (в нашем примере - `http://192.168.1.1:1234`) для дальнейшей настройки.

## II. Настройка

Дальнейший вариант настройки является лишь рекомендацией. Меняйте всё, что считаете нужным, под свои нужды.

Почему именно Сomss главный DNS-сервер?

Он позволяет обойти ограничения для сайтов, которые сами блокируют доступ пользователям из России. Например ChatGPT, Google Gemini, Canva, обновления антивирусов, инсайдерские сборки и обновления Windows, Brawl Stars, сетевые режимы Doom Eternal и многое другое, но не все подобные сайты.
Актуальные адреса DNS Comss всегда можно найти по этой ссылке: [https://www.comss.ru/page.php?id=7315](https://www.comss.ru/page.php?id=7315)

Для Instagram, Facebook и X (Twitter) нужны другие DNS-сервера так как они предоставляют незаблокированные европейские IP-адреса так как Comss выдает заблокированные. Это актуально для тех, у кого установлен NFQWS или zapret.

Начнем настройку.

Нажмите в самом верху на "Настройки" → "Основные настройки":

Раздел "Настройка журнала":

*   Уберите галочку с "Включить журнал" (рекомендую включать в ситуациях, только когда это действительно нужно чтобы не тратить попусту ресурс вашей флешки/внутренней памяти роутера).
*   Выберите `24 часа` в "Частота ротации журнала запросов"

Раздел "Конфигурация статистики":

*   Поставьте галочку на "Включить статистику"
*   Выберите `24 часа` в "Сохранение статистики"

Нажмите в самом верху на "Настройки" → "Настройки DNS":

**Upstream DNS-серверы**

 ```bash
https://router.comss.one/dns-query
https://dns.comss.one/dns-query
tls://dns.comss.one
quic://dns.comss.one
#Соцсети
[/cdninstagram.com/facebook.com/facebook.net/fbcdn.com/fbcdn.net/ig.me/instagram.com/facebook.com.es/facebook.com.vn/facebook.fr/fb.com/fb.me/fbsbx.com/licdn.com/tfbnw.net/thefacebook.com/akamaized.net/twimg.com/twitter.com/x.com/tweetdeck.com/t.co/]https://ns1.opennameserver.org/dns-query https://ns2.opennameserver.org/dns-query https://ns3.opennameserver.org/dns-query
```

**Резервные DNS-серверы**

 ```bash
https://common.dot.dns.yandex.net/dns-query
https://dns.adguard-dns.com/dns-query
https://dns.quad9.net/dns-query
https://dns.nextdns.io
https://doh.opendns.com/dns-query
https://freedns.controld.com/p0
https://dns.cloudflare.com/dns-query
https://dns.google/dns-query
tls://common.dot.dns.yandex.net
tls://dns.adguard-dns.com
tls://dns.quad9.net
tls://dns.nextdns.io
tls://dns.opendns.com
tls://p0.freedns.controld.com
tls://one.one.one.one
tls://dns.google
```

**Bootstrap DNS-серверы**

 ```bash
1.1.1.1
1.0.0.1
8.8.8.8
8.8.4.4
77.88.8.8
77.88.8.1
9.9.9.10
149.112.112.10
```

Дальнейшая настройка нужна **ТОЛЬКО** для блокировки рекламы (если это не нужно, то пропускайте):

Нажмите в самом верху на "Фильтры" → "Чёрные списки DNS"

 ```bash
https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
https://schakal.ru/hosts/alive_hosts.txt
https://raw.githubusercontent.com/Zalexanninev15/NoADS_RU/main/ads_list_extended.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_6.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_23.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_50.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_59.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_60.txt
```


Удалите два чёрных списка которые уже есть. Нажмите на "Добавить чёрный список" → "Добавить свой список". Далее вставляйте по одной ссылке без ввода имени (оно потом само появится при добавлении) и нажимайте "Сохранить".

Эта настройка нужна для разблокировки проверенных доменов, независимо от их наличия в черных списках (если это не нужно, то тоже пропускайте):

Нажмите в самом верху на "Фильтры" → "Пользовательские правила фильтрации":

 ```bash
@@||piwik.opendesktop.org^
important
@@||yt3.ggpht.com^
important
@@||suggestqueries.google.com^
important
@@||hl-img.peco.uodoo.com^
important
@@||gstaticadssl.l.google.com^
important
@@||stat.online.sberbank.ru^
important
@@||jnn-pa.googleapis.com^
important
@@||osb-apps-v2.samsungqbe.com^$important
```


## III. Решение возможных проблем

1.  Если не загружаются сайты, которые проксирует через себя Comss (например, `chatgpt.com` или `canva.com`), выполните следующие действия:

    *   Отключите использование безопасного DNS-сервера в браузере. Например, в Google Chrome это можно сделать в разделе "Конфиденциальность и безопасность" → "Безопасность" → "Использовать безопасный DNS"
    *   Очистите кэш браузера после его закрытия. Перед этим убедитесь, что браузер не работает в фоновом режиме
    *   Если вышеуказанные действия не помогли, проверьте загрузку сайтов через Comss в другом браузере

2.  Если не обновляются подписки по HTTPS:

    Установите дополнительные пакеты через консоль с помощью Entware:

    ```bash
    opkg update
    opkg install ca-bundle
    opkg install ca-certificates
    ```

3.  Периодически перестают открываться веб-страницы. В веб-интерфейсе управления роутером видна загрузка процессора на `98-99%`:

    Отключите в настройках AdGuard Home функции "Безопасная навигация" и "Родительский контроль". Если это поможет, значит, процессор роутера не справляется с нагрузкой, создаваемой этими функциями.

4.  Если необходимо удалить AdGuard Home:

    1.  Остановите его:

        ```bash
        /opt/etc/init.d/S99adguardhome stop
        ```

    2.  Удалите AdGuard Home:

        ```bash
        opkg remove adguardhome-go
        ```

    3.  Включите встроенный DNS-сервер прошивки Keenetic.

        Для этого подключитесь к CLI, перейдя по адресу `http://192.168.1.1/a` или используйте свой актуальный адрес роутера вместо `192.168.1.1`

        Выполните команды:

        ```bash
        no opkg dns-override
        system configuration save
        ```
