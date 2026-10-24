# Otel Yönetim Sistemi

Flask ve MySQL kullanılarak geliştirilen otel yönetim sistemi. Proje; oda,
misafir, rezervasyon, konaklama, ödeme ve ek hizmet verilerini yönetmek için
ilişkisel veritabanı altyapısını içerir.

## Teknolojiler

- Python 3
- Flask
- MySQL 8.0 / InnoDB
- Flask-SQLAlchemy ve PyMySQL

## Başlangıç

1. MySQL 8.0 sunucusunu kurup çalıştırın.
2. Veritabanı tablolarını, kuralları ve örnek verileri [veritabanı rehberindeki](DATABASE.md)
   sırayla oluşturun.
3. Sanal ortamı etkinleştirip bağımlılıkları kurun:

   ```powershell
   .\venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```

4. `.env.example` dosyasını `.env` olarak kopyalayıp veritabanı ve `SECRET_KEY`
   ayarlarını girin.
5. Uygulamayı başlatın ve bağlantıyı `http://127.0.0.1:5000/api/health`
   adresinden kontrol edin:

   ```powershell
   python main.py
   ```

## Veritabanı kapsamı

Şema 13 tablo, sezonluk oda fiyatları, tarih çakışmasını veritabanında engelleyen
tetikleyiciler, check-in/check-out işlemleri, saklı yordamlar, görünümler ve örnek
veriler içerir. Ayrıntılı kurulum komutları ve SQL kullanımı için
[DATABASE.md](DATABASE.md) dosyasına bakın.

## Test

```powershell
python -m unittest discover -s tests -v
```

> Proje geliştirme aşamasındadır. Mevcut Flask API başlangıç ve sağlık kontrolü
> içerir; rezervasyon ve kullanıcı uç noktaları henüz tamamlanmamıştır.
