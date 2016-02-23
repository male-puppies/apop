
#!/bin/sh


if [ $# -eq 0 ]; then
        echo "usage:"     
        echo "    ugw_factory_mac -set mac '78:d3:8d:aa:bb:c1'"
        echo "    ugw_factory_mac -read mac"
        exit
fi

if [ "$1""z" == "-read""z" ]; then
	echo -e "\n AC-MAC: "

	dd if=/dev/mtd2 bs=2 skip=28672 count=3 2>/dev/null | hexdump -v -n 6 -e '5/1 "%02x:" 1/1 "%02x"'
	echo -e "\n\n"
	exit
fi



if [ "$1""z" != "-set""z" ]; then
	exit
fi


if [ "$2""z" == "mac""z" ]; then
		local mac=$3
		echo -ne \\x${mac//:/\\x}  |  dd of=/dev/mtdblock2 bs=2 seek=28672 count=3
		exit
fi

