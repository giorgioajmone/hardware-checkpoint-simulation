int getchar();
int putchar(int c);


int compter_uns(int x)
{
    int res;

    res = 0;
    while(x != 0)
    {
        res = (res + (x % 2)) % 2;
        x = x / 2;
    }
    
    return res;
}

void thuemorse(int n)
{
    int i;

    for(i = 0; i < n; i++)
        putchar('0' + compter_uns(i));
    putchar(10);
}

int main()
{
    thuemorse(128);
    return 0;
}



