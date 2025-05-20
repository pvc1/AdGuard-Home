Нравится проект? Поддержи аренду сервера через [CloudTips](https://pay.cloudtips.ru/p/ddeac224) или [Юмани](https://yoomoney.ru/to/41001945296522) или скинь на чашечку кофе ☕ 

***

# Установка и настройка AdGuard Home

> [!IMPORTANT]
> Автор не несет ответственности за неправомерное использование данного материала.  
> Вы пользуетесь этой инструкцией на свой страх и риск!  
> Автор не несёт ответственности за порчу оборудования, программного обеспечения и любых подобных проблем.  
> Подразумевается, что вы понимаете, что вы делаете.

> [!WARNING]
> ВНИМАНИЕ!  
> В настоящее время наблюдаются перебои в работе [Comss DNS](https://www.comss.ru/page.php?id=7315), как из-за блокировок зарубежных хостеров Роскомнадзором, так и из-за блокировок со стороны самого Google для своих сервисов, когда одновременно очень много человек пользуются одним прокси-сервером.  
> В разделе [«Настройки DNS»](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#3-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B8-dns) указан дополнительный список DNS для работы с нейросетями.

Содержание [Wiki](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home):

I. [Установка AdGuard Home](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#i-%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-adguard-home)<br>
1. [Для роутеров Keenetic](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#1-%D0%B4%D0%BB%D1%8F-%D1%80%D0%BE%D1%83%D1%82%D0%B5%D1%80%D0%BE%D0%B2-keenetic)<br>
2. [Для роутеров на прошивках OpenWRT](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#2-%D0%B4%D0%BB%D1%8F-%D1%80%D0%BE%D1%83%D1%82%D0%B5%D1%80%D0%BE%D0%B2-%D0%BD%D0%B0-%D0%BF%D1%80%D0%BE%D1%88%D0%B8%D0%B2%D0%BA%D0%B0%D1%85-openwrt)<br>
3. [Для роутеров ASUS](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#3-%D0%B4%D0%BB%D1%8F-%D1%80%D0%BE%D1%83%D1%82%D0%B5%D1%80%D0%BE%D0%B2-asus)<br>
4. [Для систем Linux (Debian, Ubuntu и т.д.)](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#4-%D0%B4%D0%BB%D1%8F-%D1%81%D0%B8%D1%81%D1%82%D0%B5%D0%BC-linux-debian-ubuntu-%D0%B8-%D1%82%D0%B4)<br>

II. [Настройка AdGuard Home](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#ii-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B0-adguard-home)<br>
1. [Общие сведения о настройке](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#1-%D0%BE%D0%B1%D1%89%D0%B8%D0%B5-%D1%81%D0%B2%D0%B5%D0%B4%D0%B5%D0%BD%D0%B8%D1%8F-%D0%BE-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B5)<br>
2. [Основные настройки](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#2-%D0%BE%D1%81%D0%BD%D0%BE%D0%B2%D0%BD%D1%8B%D0%B5-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B8)<br>
3. [Настройки DNS](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#3-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B8-dns)<br>
4. [Блокировка рекламы (опционально)](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#4-%D0%B1%D0%BB%D0%BE%D0%BA%D0%B8%D1%80%D0%BE%D0%B2%D0%BA%D0%B0-%D1%80%D0%B5%D0%BA%D0%BB%D0%B0%D0%BC%D1%8B-%D0%BE%D0%BF%D1%86%D0%B8%D0%BE%D0%BD%D0%B0%D0%BB%D1%8C%D0%BD%D0%BE)<br>
5. [Разблокировка проверенных доменов (опционально)](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#5-%D1%80%D0%B0%D0%B7%D0%B1%D0%BB%D0%BE%D0%BA%D0%B8%D1%80%D0%BE%D0%B2%D0%BA%D0%B0-%D0%BF%D1%80%D0%BE%D0%B2%D0%B5%D1%80%D0%B5%D0%BD%D0%BD%D1%8B%D1%85-%D0%B4%D0%BE%D0%BC%D0%B5%D0%BD%D0%BE%D0%B2-%D0%BE%D0%BF%D1%86%D0%B8%D0%BE%D0%BD%D0%B0%D0%BB%D1%8C%D0%BD%D0%BE)<br>

III. [Решение возможных проблем](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#iii-%D1%80%D0%B5%D1%88%D0%B5%D0%BD%D0%B8%D0%B5-%D0%B2%D0%BE%D0%B7%D0%BC%D0%BE%D0%B6%D0%BD%D1%8B%D1%85-%D0%BF%D1%80%D0%BE%D0%B1%D0%BB%D0%B5%D0%BC)
1. [Не работает Comss DNS](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#1-%D0%BD%D0%B5-%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D0%B0%D0%B5%D1%82-comss-dns)
2. [Не обновляются подписки по HTTPS](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#2-%D0%BD%D0%B5-%D0%BE%D0%B1%D0%BD%D0%BE%D0%B2%D0%BB%D1%8F%D1%8E%D1%82%D1%81%D1%8F-%D0%BF%D0%BE%D0%B4%D0%BF%D0%B8%D1%81%D0%BA%D0%B8-%D0%BF%D0%BE-https)
3. [Загрузка процессора на 98-99%](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#3-%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BA%D0%B0-%D0%BF%D1%80%D0%BE%D1%86%D0%B5%D1%81%D1%81%D0%BE%D1%80%D0%B0-%D0%BD%D0%B0-98-99)
4. [Удаление AdGuard Home](https://github.com/Internet-Helper/AdGuard-Home/wiki/AdGuard-Home#4-%D1%83%D0%B4%D0%B0%D0%BB%D0%B5%D0%BD%D0%B8%D0%B5-adguard-home)
