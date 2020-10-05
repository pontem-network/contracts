MY_GUY=wallet12tg20s9g4les55vfvnumlkg0a5zk825py9j0ha
mnemonic="bicycle adapt detect exclude check shift bullet fetch divorce dinner boss crouch stadium autumn long grape ready expire vivid green cloud there wash busy"

echo $mnemonic | dncli keys add --dry-run --recover myguy
