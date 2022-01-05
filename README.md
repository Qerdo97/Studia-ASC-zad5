# Studia-ASC-zad5
Zadanie do wykonania Skrypt ma być łatwo modyfikowalny

- należy posługiwać się zmiennymi, dane statyczne nie są dopuszczalne

- Komentarze do wykonywanych operacji (obowiązkowe)

1) Zadać pytanie o poświadczenia z azure active directory

2) Utworzyć grupę zasobów o nazwie "Numer indeksu", wszystkie zasoby mają być gromadzone w tej grupie

3) Utworzyć siec wirtualną o adresacji (10 -90).(10 -90).0.0/16 - nazwa WITNET_numerindeksu

4) Utworzyć podsieć o adresacji (10 -90).(10 -90).(10 -90).0/24 - nazwa WITSUBNET_numerindeksu

5) Utworzyć maszyny wirtualne WIT_Numerindeksu_VM1/VM2 - maszyny mają używać sieci utworzonej w punktach 3 i 4 - system operacyjny Windows Server 2019 Datacenter - login i hasło do maszyn "WitAdmin"/Pa$$w0rd123456

6) Utworzyć grupy aplikacji Indeks_AG_PSWWW i Indeks_AG_MGM

7) Utworzyć reguły sieciowe:

- nazwa Indeks_PS - dozwolony port 5985, ruch dozwolony tylko do grupy aplikacji Indeks_AG_PSWWW

- nazwa Indeks_WWW - dozwolone porty 9090,443, ruch dozwolony tylko do grupy aplikacji Indeks_AG_PSWWW

 - nazwa Indeks_MGM - dozwolone porty 3389, ruch dozwolony tylko do grupy aplikacji Indeks_AG_MGM

8) Utworzyć sieciową grupę zabezpieczeń o nazwie Indeks_NSG i dodać do niej reguły z punktu 7

9) Przypisać grupę NSG z punktu 8 do obu maszyn wirtualnych

10) Przypisać grupę ASG Indeks_AG_PSWWW do WIT_Numerindeksu_VM2

11) Przypisać grupę ASG Indeks_AG_MGM do WIT_Numerindeksu_VM1

12) Utworzyć skrypt z zawartością podaną w Notatkach  

13) Za pomocą PowerShell wykonać zdalnie skrypt z punktu 12

14) Sprawdzić publiczne IP dla maszyny WIT_Numerindeksu_VM2

15) Za pomocą PowerShell wyzwolić przeglądarkę internetową i wyświetlić stronę utrzymywaną przez maszynę WIT_Numerindeksu_VM2

16) Wykonać listę utworzonych obiektów z informacją o przypisanych Tagach

17) Wyłączyć maszyny zwalniając wszystkie używane przez nie zasoby
